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
  # │ ByeDPI (127.0.0.1:6430)                                      │
  # │ - локальный SOCKS5-прокси для обхода DPI                    │
  # │ - фильтрует по hosts.txt сам, sing-box не вмешивается        │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - ciadpi (ByeDPI) → bypass (чтобы не зациклиться)           │
  # │ - QUIC (UDP/443, UDP/8443) → direct                         │
  # │ - NTP (UDP/123) → direct                                     │
  # │ - Firefox → byedpi-out                                       │
  # │ - Brave → socks-out (внешний SOCKS5)                         │
  # │ - Chromium → vless-out                                       │
  # │ - Всё остальное → direct                                     │
  # └─────────────────────────────────────────────────────────────┘
  # =====================================================================
  services.sing-box = {
    enable = true;
    settings = {
      # log.level: info — штатный режим. debug включать только для отладки.
      log = {
        level = "info";
      };

      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";

          # address: IPv4 + IPv6 префиксы. IPv6 (ULA) нужен,
          # чтобы заворачивать IPv6-трафик в TUN.
          address = [
            "172.19.0.1/30"
            "fdfe:dcba:9876::1/126"
          ];

          # dns_mode = "disabled": sing-box НЕ перехватывает DNS.
          # DNS обслуживает связка dnscrypt-proxy → DoH.
          dns_mode = "disabled";

          # auto_route: создаёт ip rule + таблицу 2022 для TUN.
          auto_route = true;

          # strict_route = false: совместимость с локальными сервисами
          # (dnscrypt-proxy, byedpi слушают на 127.0.0.1).
          strict_route = false;

          mtu = 1400;

          # stack = "gvisor" — КРИТИЧНО.
          # sing-box терминирует TCP в userspace и открывает НОВЫЙ сокет
          # от имени системы с src=физический IP. MASQUERADE не нужен.
          #
          # НЕ использовать "mixed" и "system":
          #   Оба используют системный стек → packet-mode.
          #   Пакет форвардится с src=172.19.0.1 (адрес TUN),
          #   upstream не может ответить → SYN-SENT.
          stack = "gvisor";
        }
      ];

      outbounds = [
        # socks-out: внешний SOCKS5 (для Brave).
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
        # ByeDPI сам решает, к каким доменам применять стратегии.
        {
          type = "socks";
          tag = "byedpi-out";
          server = "127.0.0.1";
          server_port = 6430;
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
        # Правило ip rule priority 100 разрывает петлю TUN.
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
          #    попадать в TUN. Иначе: ByeDPI → sing-box → byedpi-out
          #    → ByeDPI → ... (бесконечная петля).
          {
            action = "bypass";
            process_name = ["ciadpi"];
          }
          # 4. NTP (UDP/123) — direct. systemd-timesyncd не должен
          #    идти через TUN.
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          # 5. QUIC (UDP/443, UDP/8443) — direct, ДО sniff.
          #    sniff не должен читать фрагментированный QUIC ClientHello
          #    (ломает pre-match). QUIC пропускается напрямую.
          {
            network = "udp";
            port = [443 8443];
            outbound = "direct-out";
          }
          # 6. Sniffing — определяет протокол для следующих правил.
          {
            action = "sniff";
          }
          # 7. Firefox → ByeDPI (byedpi-out).
          #    Firefox ходит через локальный SOCKS5 ByeDPI.
          #    ByeDPI сам фильтрует по hosts.txt.
          {
            process_name = ["firefox"];
            outbound = "byedpi-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*"];
            outbound = "byedpi-out";
          }
          # 8. Brave → внешний SOCKS5 (socks-out).
          {
            process_name = ["brave"];
            outbound = "socks-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "socks-out";
          }
          # 9. Chromium → VLESS.
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # 10. Fallback: всё остальное → direct.
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

      # ExecStop — отдельный shell-скрипт, чтобы `|| true` работал.
      ExecStop = pkgs.writeShellScript "sing-box-fwmark-stop" ''
        ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      '';
    };

    # script → NixOS оборачивает в bash. Идемпотентное добавление.
    script = ''
      ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true

      ${pkgs.iproute2}/bin/ip    rule add fwmark 8227 lookup main priority 100
      ${pkgs.iproute2}/bin/ip -6 rule add fwmark 8227 lookup main priority 100
    '';
  };
}
