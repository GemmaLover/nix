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
  # │ Трафик направляется в outbound "zapret-out" с              │
  # │ routing_mark = 110. nftables видит метку и заворачивает    │
  # │ пакеты в очередь 200, где nfqws2 применяет стратегии.      │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - Chromium → vless-out                                       │
  # │ - Всё остальное → zapret-out (через nfqws2)                  │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - routing_mark = 110 в OUTBOUND — это правильный способ
  #   помечать пакеты для nfqws2. В TUN inbound такой опции НЕТ.
  # - default_mark = 8227 — помечает все исходящие сокеты sing-box
  #   (для разрыва петли через TUN). Это отдельная метка.
  # - stack = "gvisor" — КРИТИЧНО.
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
        # zapret-out — специальный outbound для nfqws2.
        # type "direct" + routing_mark = 110.
        # sing-box просто помечает трафик, а nftables
        # перенаправляет помеченные пакеты в NFQUEUE.
        {
          type = "direct";
          tag = "zapret-out";
          routing_mark = 110;
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
          # 2. dnscrypt-proxy — direct (без nfqws2).
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
          # 4. Chromium → VLESS (без nfqws2).
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # 5. Fallback: всё остальное → zapret-out
          #    (в том числе Firefox и Brave, которые пойдут через nfqws2).
          {
            outbound = "zapret-out";
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
