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
  # │ dnscrypt-proxy (127.0.0.1:53) → DoH TCP-only                │
  # ├─────────────────────────────────────────────────────────────┤
  # │ ByeDPI (127.0.0.1:6430) — для Firefox                       │
  # │ zapret2/tpws (127.0.0.1:3472) — для Brave                   │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - Firefox → byedpi-out                                       │
  # │ - Brave → zapret2-out (SOCKS5 :3472)                         │
  # │ - Chromium → vless-out                                       │
  # │ - ciadpi и tpws → bypass (чтобы не зациклиться)             │
  # │ - Всё остальное → direct                                     │
  # └─────────────────────────────────────────────────────────────┘
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

          # gvisor — TCP termination в userspace. Критично.
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
        # byedpi-out — для Firefox.
        {
          type = "socks";
          tag = "byedpi-out";
          server = "127.0.0.1";
          server_port = 6430;
          version = "5";
        }
        # zapret2-out — для Brave (tpws в SOCKS-режиме).
        {
          type = "socks";
          tag = "zapret2-out";
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
          # ciadpi (ByeDPI) — bypass.
          {
            action = "bypass";
            process_name = ["ciadpi"];
          }
          # tpws (zapret2) — bypass.
          # Процесс tpws сам генерирует трафик, который не должен
          # попадать в TUN. Иначе петля: tpws → sing-box → zapret2-out
          # → tpws → ...
          {
            action = "bypass";
            process_name = ["tpws"];
          }
          # NTP — direct.
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          # QUIC — direct, ДО sniff.
          {
            network = "udp";
            port = [443 8443];
            outbound = "direct-out";
          }
          # Sniffing для TCP.
          {
            action = "sniff";
          }
          # Firefox → ByeDPI.
          {
            process_name = ["firefox"];
            outbound = "byedpi-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*"];
            outbound = "byedpi-out";
          }
          # Brave → zapret2 (tpws SOCKS5).
          {
            process_name = ["brave"];
            outbound = "zapret2-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "zapret2-out";
          }
          # Chromium → VLESS.
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # Fallback → direct.
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
