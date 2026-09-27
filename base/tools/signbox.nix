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
  # │ - UDP/QUIC (HTTP/3, DoH3) → пробрасывается через            │
  # │   стек mixed с включённой фрагментацией.                     │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - DNS-секции нет. sing-box не резолвит имена.
  # - default_mark = 8227 (0x2023) — помечает исходящие сокеты sing-box.
  #   Правило ip rule (v4+v6) создаётся сервисом sing-box-fwmark-rule.
  # - stack = "mixed": TCP через system (надёжно), UDP через gvisor
  #   (быстрее, но требует udp_fragment = true для QUIC).
  # - udp_fragment = true — КРИТИЧНО для QUIC/HTTP3. Без этого
  #   фрагментированные QUIC-пакеты теряются, DoH3 и HTTP/3 зависают.
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
          #  - UDP (QUIC, DoH3) обрабатывается gvisor с фрагментацией.
          stack = "mixed";

          # Разрешаем фрагментацию UDP. Без этого QUIC ClientHello,
          # не влезающий в один пакет, теряется, и соединение виснет.
          udp_fragment = true;

          # Время жизни UDP-сессии (NAT expiration).
          # 5 минут — стандарт, совместим с большинством приложений.
          udp_timeout = "5m";
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
  #
  # КРИТИЧНО:
  # - Скрипт ИДЕМПОТЕНТЕН: удаляет старые правила, затем добавляет новые.
  # - Используется `script`, а НЕ многострочный ExecStart/ExecStop.
  # - Нужны ДВА правила: IPv4 и IPv6.
  # - priority 100 — выше auto_route (9000-9010).
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
