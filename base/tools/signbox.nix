{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # sing-box — маршрутизация TCP/UDP-трафика по процессам.
  #
  # Модель трафика:
  # ┌─────────────────────────────────────────────────────────────┐
  # │ dnscrypt-proxy (127.0.0.1:53 и :5353)                       │
  # │ - шифрует DNS (DoH) → Cloudflare/Quad9/Scaleway             │
  # │ - HTTP/3 отключён, TCP-ONLY                                  │
  # ├─────────────────────────────────────────────────────────────┤
  # │ ByeDPI (127.0.0.1:6430) — локальный SOCKS5 для Firefox       │
  # │ zapret/tpws (127.0.0.1:3472) — локальный SOCKS5 для Brave    │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - ciadpi (ByeDPI) → bypass                                   │
  # │ - tpws (zapret) → bypass                                     │
  # │ - QUIC (UDP/443, UDP/8443) → direct                         │
  # │ - NTP (UDP/123) → direct                                     │
  # │ - Firefox → byedpi-out                                       │
  # │ - Brave → zapret-out                                         │
  # │ - Chromium → vless-out                                       │
  # │ - Всё остальное → direct                                     │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - DNS-секции нет. sing-box не резолвит имена.
  # - default_mark = 8227 (0x2023) — помечает исходящие сокеты sing-box.
  #   Правило ip rule (v4+v6) создаёт сервис sing-box-fwmark-rule.
  #
  # - stack = "gvisor" — КРИТИЧНО.
  #   sing-box терминирует TCP в userspace и открывает НОВЫЙ сокет
  #   от имени системы с src=физический IP. MASQUERADE не нужен.
  #
  #   Почему НЕ "mixed" и НЕ "system":
  #   Оба используют системный стек для TCP → packet-mode.
  #   Пакет форвардится с исходным src=172.19.0.1 (адрес TUN).
  #   Этот адрес приватный, upstream не может ответить → SYN-SENT.
  #   Нужен MASQUERADE, который мы убрали. Отсюда зависание DNS
  #   (dnscrypt-proxy не может подключиться к DoH-серверам)
  #   и новые сайты не открываются.
  #
  # - ПРАВИЛА BYPASS ДЛЯ ciadpi и tpws:
  #   ByeDPI и zapret генерируют исходящий трафик, который
  #   не должен попадать в TUN. Иначе бесконечная петля:
  #   процесс → sing-box → byedpi-out/zapret-out → процесс → ...
  #   action = "bypass" означает: пропустить этот трафик
  #   напрямую через системный стек, не перехватывая.
  #
  # - ПРАВИЛО ДЛЯ QUIC:
  #   { network = "udp"; port = [443 8443]; outbound = "direct-out"; }
  #   Ставится ДО sniff, чтобы sniff не пытался читать
  #   фрагментированный QUIC ClientHello.
  #
  # - auto_redirect ОТКЛЮЧЁН. Используем auto_route.
  # - sniff на inbound в sing-box 1.14 УБРАН.
  # =====================================================================
  services.sing-box = {
    enable = true;
    settings = {
      log = {
        level = "info";
      };

      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";

          # IPv4 + IPv6 префиксы для TUN-интерфейса.
          address = [
            "172.19.0.1/30"
            "fdfe:dcba:9876::1/126"
          ];

          # dns_mode = "disabled": sing-box НЕ перехватывает DNS.
          dns_mode = "disabled";

          # auto_route: создаёт ip rule + таблицу 2022 для TUN.
          auto_route = true;

          # strict_route = false: совместимость с локальными сервисами.
          strict_route = false;

          mtu = 1400;

          # gvisor — TCP termination в userspace.
          stack = "gvisor";
        }
      ];

      outbounds = [
        # socks-out: внешний SOCKS5 (резервный).
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";
          server_port = 1080;
          version = "5";
          username = "chelik";
          password = "pass11";
        }
        # byedpi-out: локальный SOCKS5 ByeDPI (для Firefox).
        {
          type = "socks";
          tag = "byedpi-out";
          server = "127.0.0.1";
          server_port = 6430;
          version = "5";
        }
        # zapret-out: локальный SOCKS5 tpws из пакета zapret (для Brave).
        {
          type = "socks";
          tag = "zapret-out";
          server = "127.0.0.1";
          server_port = 3472;
          version = "5";
        }
        # vless-out: VLESS с XTLS-Vision (для Chromium).
        {
          type = "vless";
          tag = "vless-out";
          server = "ВАШ_СЕРВЕР";
          server_port = 443;
          uuid = "ВАШ_UUID";
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН";
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }
        # direct-out: выход напрямую через физический интерфейс.
        {
          type = "direct";
          tag = "direct-out";
        }
      ];

      route = {
        find_process = true;
        auto_detect_interface = true;

        # default_mark = 8227 (0x2023): помечает исходящие сокеты sing-box.
        default_mark = 8227;

        rules = [
          # 1. Локальные адреса — всегда direct.
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          # 2. dnscrypt-proxy — direct. Без этого DNS зациклится.
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          # 3. ciadpi (ByeDPI) — bypass.
          #    Процесс ByeDPI сам генерирует трафик, который не должен
          #    попадать в TUN. Иначе бесконечная петля.
          {
            action = "bypass";
            process_name = ["ciadpi"];
          }
          # 4. tpws (zapret) — bypass.
          #    Процесс tpws сам генерирует трафик, который не должен
          #    попадать в TUN. Иначе бесконечная петля.
          {
            action = "bypass";
            process_name = ["tpws"];
          }
          # 5. NTP (UDP/123) — direct.
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          # 6. QUIC (UDP/443, UDP/8443) — direct, ДО sniff.
          {
            network = "udp";
            port = [443 8443];
            outbound = "direct-out";
          }
          # 7. Sniffing — определяет протокол для следующих правил.
          {
            action = "sniff";
          }
          # 8. Firefox → ByeDPI (byedpi-out).
          {
            process_name = ["firefox"];
            outbound = "byedpi-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*"];
            outbound = "byedpi-out";
          }
          # 9. Brave → zapret (tpws SOCKS5).
          {
            process_name = ["brave"];
            outbound = "zapret-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "zapret-out";
          }
          # 10. Chromium → VLESS.
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # 11. Fallback: всё остальное → direct.
          {
            outbound = "direct-out";
          }
        ];
      };
    };
  };

  # =====================================================================
  # Capabilities и PATH для sing-box.
  # CAP_NET_ADMIN — работа с TUN и ip rule.
  # CAP_NET_RAW — работа с сокетами низкого уровня.
  # CAP_NET_BIND_SERVICE — привязка к привилегированным портам.
  # CAP_SYS_PTRACE — определение процесса по сокету (find_process).
  # =====================================================================
  systemd.services.sing-box.serviceConfig = {
    AmbientCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
      "CAP_SYS_PTRACE"
    ];
    CapabilityBoundingSet = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
      "CAP_SYS_PTRACE"
    ];
    path = [pkgs.nftables pkgs.iptables pkgs.iproute2];
  };

  # =====================================================================
  # Правила маршрутизации для fwmark 0x2023 (IPv4 + IPv6).
  #
  # Идемпотентный скрипт: сначала удаляет старые правила, затем добавляет.
  # Это защищает от ошибки "RTNETLINK answers: File exists" при рестарте.
  #
  # priority 100 — выше auto_route (9000-9010), поэтому срабатывает
  # раньше и выводит пакеты sing-box из петли через TUN.
  #
  # Нужны ДВА правила (IPv4 и IPv6):
  #  - IPv4: для стандартных соединений sing-box.
  #  - IPv6: для DoH/QUIC-соединений, которые dnscrypt-proxy
  #    открывает через IPv6 (иначе они зацикливаются в TUN).
  # =====================================================================
  systemd.services.sing-box-fwmark-rule = {
    description = "Add ip rule for sing-box default_mark (break TUN loop, v4+v6)";
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStop = pkgs.writeShellScript "sing-box-fwmark-stop" ''
        ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      '';
    };

    script = ''
      ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true

      ${pkgs.iproute2}/bin/ip    rule add fwmark 8227 lookup main priority 100
      ${pkgs.iproute2}/bin/ip -6 rule add fwmark 8227 lookup main priority 100
    '';
  };
}
