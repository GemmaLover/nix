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
  # - ПРАВИЛА BYPASS ДЛЯ ciadpi и tpws:
  #   ByeDPI и zapret генерируют исходящий трафик, который
  #   не должен попадать в TUN. Иначе бесконечная петля.
  #   action = "bypass" означает: пропустить этот трафик
  #   напрямую через системный стек, не перехватывая.
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

          address = [
            "172.19.0.1/30"
            "fdfe:dcba:9876::1/126"
          ];

          dns_mode = "disabled";
          auto_route = true;
          strict_route = false;
          mtu = 1400;
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
        {
          type = "socks";
          tag = "byedpi-out";
          server = "127.0.0.1";
          server_port = 6430;
          version = "5";
        }
        {
          type = "socks";
          tag = "zapret-out";
          server = "127.0.0.1";
          server_port = 3472;
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
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          {
            action = "bypass";
            process_name = ["ciadpi"];
          }
          {
            action = "bypass";
            process_name = ["tpws"];
          }
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          {
            network = "udp";
            port = [443 8443];
            outbound = "direct-out";
          }
          {
            action = "sniff";
          }
          {
            process_name = ["firefox"];
            outbound = "byedpi-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*"];
            outbound = "byedpi-out";
          }
          {
            process_name = ["brave"];
            outbound = "zapret-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "zapret-out";
          }
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          {
            outbound = "direct-out";
          }
        ];
      };
    };
  };

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
