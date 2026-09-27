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
  # │ - работает независимо от sing-box                           │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - ciadpi (ByeDPI) → bypass (чтобы не зациклиться)           │
  # │ - QUIC (UDP/443, UDP/8443) → direct                         │
  # │ - NTP (UDP/123) → direct                                     │
  # │ - Brave → byedpi-out (локальный SOCKS5 ByeDPI)              │
  # │ - Chromium → VLESS                                           │
  # │ - Firefox, nix, всё остальное → direct                       │
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
  # - ПРАВИЛО BYPASS ДЛЯ ciadpi:
  #   ByeDPI — это отдельный процесс, который тоже генерирует
  #   исходящий трафик. Если этот трафик попадёт в TUN sing-box,
  #   возникнет петля: ByeDPI → sing-box → ByeDPI → ...
  #   Поэтому для процесса ciadpi стоит action = "bypass".
  #   Bypass означает "не перехватывать, отдать системе напрямую".
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

          dns_mode = "disabled";

          auto_route = true;
          strict_route = false;
          mtu = 1400;

          # gvisor — TCP termination в userspace.
          stack = "gvisor";
        }
      ];

      outbounds = [
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";
          server_port = 1080;
          version = "5";
          username = "chelik";
          password = "pass11";
        }
        # =============================================================
        # НОВЫЙ OUTBOUND: ByeDPI
        #
        # Локальный SOCKS5-прокси, который поднимает ByeDPI.
        # Brave будет направляться на него через правило
        # process_name = ["brave"] ниже.
        #
        # ByeDPI обходит DPI на уровне TCP-десинхронизации.
        # Он не требует VLESS и работает напрямую с провайдером,
        # подменяя/разбивая пакеты так, чтобы DPI не мог
        # распознать SNI.
        #
        # ВАЖНО:
        # - ByeDPI — это SOCKS5, не VLESS. Он не шифрует трафик,
        #   а маскирует его от DPI. Подходит для сайтов,
        #   которые блокируются по SNI (YouTube, Discord и т.п.).
        # - Если сайт заблокирован по IP (а не по SNI),
        #   ByeDPI не поможет — нужен VLESS.
        # =============================================================
        {
          type = "socks";
          tag = "byedpi-out";
          server = "127.0.0.1";
          server_port = 6430;
          version = "5";
        }
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
        {
          type = "direct";
          tag = "direct-out";
        }
      ];

      route = {
        find_process = true;
        auto_detect_interface = true;
        default_mark = 8227;

        rules = [
          # 1. Локальные адреса — всегда direct.
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          # 2. Служебные процессы — direct (чтобы не зациклить DNS).
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          # 3. ByeDPI (ciadpi) — BYPASS.
          #    Процесс ByeDPI сам генерирует трафик, который
          #    не должен попадать в TUN. Иначе:
          #    ByeDPI → sing-box → byedpi-out → ByeDPI → ...
          #    Это бесконечная петля.
          #    action = "bypass" означает: пропустить этот трафик
          #    напрямую через системный стек, не перехватывая.
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
          #    sniff не должен пытаться читать фрагментированный
          #    QUIC ClientHello. Пропускаем QUIC напрямую.
          {
            network = "udp";
            port = [443 8443];
            outbound = "direct-out";
          }
          # 6. Sniffing для остального трафика (TCP).
          {
            action = "sniff";
          }
          # 7. Brave → ByeDPI.
          #    Brave ходит на локальный SOCKS5 ByeDPI.
          #    Это НЕ внешний прокси — ByeDPI сам обходит DPI
          #    на уровне TCP.
          {
            process_name = ["brave"];
            outbound = "byedpi-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "byedpi-out";
          }
          # 8. Chromium → VLESS.
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # 9. Всё остальное — direct.
          {
            outbound = "direct-out";
          }
        ];
      };
    };
  };

  # =====================================================================
  # Capabilities и PATH для sing-box.
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
