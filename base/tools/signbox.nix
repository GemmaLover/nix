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
  # │ - QUIC (UDP/443, UDP/8443) → REJECT                          │
  # │   Клиенты автоматически откатываются на TCP.                 │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - DNS-секции нет. sing-box не резолвит имена.
  # - default_mark = 8227 (0x2023) — помечает исходящие сокеты sing-box.
  #   Правило ip rule (v4+v6) создаётся сервисом sing-box-fwmark-rule.
  # - stack = "mixed": TCP через system, UDP через gvisor.
  # - udp_mapping / udp_filtering — endpoint_independent.
  # - udp_timeout = "5m".
  #
  # - ГЛАВНОЕ: правило { protocol = "quic"; action = "reject"; }
  #   стоит ПЕРЕД sniff. Это блокирует все QUIC-пакеты
  #   (HTTP/3, DoH3, любой UDP-based QUIC).
  #   Причина: gvisor-стек sing-box не умеет корректно
  #   пробрасывать QUIC (фрагментированный ClientHello теряется,
  #   ответы не возвращаются, соединение виснет).
  #   Браузеры и dnscrypt-proxy при отказе QUIC автоматически
  #   переключаются на TCP — а TCP через TUN работает надёжно.
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
          stack = "mixed";
          udp_timeout = "5m";
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
          {
            process_name = ["portmaster-core"];
            outbound = "direct-out";
          }
          # 3. БЛОКИРУЕМ QUIC. Ставим ДО sniff, чтобы sniffing
          #    не пытался читать фрагментированный QUIC ClientHello
          #    (это ломает pre-match и соединение зависает).
          #    После reject клиенты (Firefox, dnscrypt-proxy) сами
          #    откатятся на TCP.
          {
            protocol = "quic";
            action = "reject";
          }
          # 4. Sniffing для остального трафика (TCP).
          {
            action = "sniff";
          }
          # 5. Правила по процессам.
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
          # 6. Всё остальное — direct.
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
