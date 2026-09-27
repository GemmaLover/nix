{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # sing-box — маршрутизация TCP/UDP-трафика по процессам.
  #
  # Модель трафика (кто чем занимается):
  # ┌─────────────────────────────────────────────────────────────┐
  # │ Portmaster (127.0.0.17:53)                                  │
  # │ - перехватывает DNS через nfqueue                           │
  # │ - фильтрует и форвардит на dnscrypt-proxy                    │
  # ├─────────────────────────────────────────────────────────────┤
  # │ dnscrypt-proxy (127.0.0.1:53 и :5353)                       │
  # │ - шифрует DNS (DoH/DNSCrypt) → Cloudflare/Quad9/Scaleway    │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - portmaster-core → direct                                   │
  # │ - Brave → SOCKS5, Chromium → VLESS                          │
  # │ - Firefox, nix, всё остальное → direct                       │
  # │ - UDP/QUIC (HTTP/3, DoH3) → stack "mixed":                  │
  # │   TCP через system, UDP через gvisor.                        │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - DNS-секции нет. sing-box не резолвит имена.
  # - default_mark = 8227 (0x2023) — помечает исходящие сокеты sing-box.
  #   Правило ip rule (v4+v6) создаётся сервисом sing-box-fwmark-rule.
  # - stack = "mixed": TCP через system (надёжно), UDP через gvisor
  #   (правильная обработка QUIC/HTTP3 без фрагментации).
  # - udp_fragment УДАЛЁН из TUN inbound в sing-box 1.14.
  #   Вместо него — udp_mapping / udp_filtering / udp_nat_max.
  #   Для QUIC эти настройки не требуются, достаточно stack = "mixed".
  # - udp_timeout = "5m" — стандартное время жизни UDP-сессии.
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

          # mixed: TCP через системный стек, UDP через gvisor.
          # Это лучший баланс для нашего кейса:
          #  - TCP (сайты) работает надёжно через system.
          #  - UDP (QUIC, DoH3) обрабатывается gvisor корректно.
          stack = "mixed";

          # udp_timeout — время жизни UDP-сессии (NAT expiration).
          # 5 минут — стандарт, совместим с большинством приложений.
          udp_timeout = "5m";

          # udp_mapping и udp_filtering — новые поля sing-box 1.14.
          # endpoint_independent (по умолчанию) — оптимально для QUIC.
          # Явно указываем для ясности, но можно и опустить.
          udp_mapping = "endpoint_independent";
          udp_filtering = "endpoint_independent";
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
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          {
            process_name = ["portmaster-core"];
            outbound = "direct-out";
          }
          {
            action = "sniff";
          }
          {
            process_name = ["brave"];
            outbound = "socks-out";
          }
          {
            process_path_regex = [".*/brave/brave.*"];
            outbound = "socks-out";
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
