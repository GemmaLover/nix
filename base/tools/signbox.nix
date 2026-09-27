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
  # │ nfqws2 (zapret2) — перехват пакетов через NFQUEUE.          │
  # │ Все пакеты, входящие в TUN, помечаются mark 110.            │
  # │ nftables видит метку и заворачивает их в очередь 200,       │
  # │ где nfqws2 применяет Lua-стратегии обхода DPI.              │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - Chromium → vless-out                                       │
  # │ - Firefox, Brave → direct (но с mark 110 → nfqws2)          │
  # │ - Всё остальное → direct                                     │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - routing_mark = 110 в inbound TUN: помечает ВСЕ пакеты,
  #   входящие в TUN. Это единственный способ заставить nftables
  #   перехватывать трафик из TUN.
  # - mark 110 исключается в nftables для dnscrypt-proxy и Chromium
  #   через отдельные правила (по портам/процессам).
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

          # routing_mark = 110: помечает ВСЕ пакеты, входящие в TUN.
          # nftables перехватывает их в очередь 200 для nfqws2.
          routing_mark = 110;
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
          # 2. dnscrypt-proxy — direct (без mark 110).
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          # 3. NTP (UDP/123) — direct.
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          # 4. Chromium → VLESS (без mark 110).
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # 5. Firefox → direct (но с mark 110 → nfqws2).
          {
            process_name = ["firefox"];
            outbound = "direct-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*"];
            outbound = "direct-out";
          }
          # 6. Brave → direct (но с mark 110 → nfqws2).
          {
            process_name = ["brave"];
            outbound = "direct-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "direct-out";
          }
          # 7. Fallback: всё остальное → direct.
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
