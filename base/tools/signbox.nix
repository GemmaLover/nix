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
  # │ пакеты в очередь 200, где nfqws2 применяет Lua-стратегии.  │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → direct                                    │
  # │ - Chromium → vless-out                                       │
  # │ - X.com: QUIC reject + TCP → direct                         │
  # │   (blockcheck показал: TCP X.com работает БЕЗ обхода,       │
  # │    блокируется только QUIC — поэтому reject UDP/443         │
  # │    заставляет Brave уйти на TCP, а TCP идёт напрямую)      │
  # │ - Всё остальное (Firefox, Brave и т.д.) → zapret-out         │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - routing_mark = 110 в OUTBOUND — правильный способ помечать
  #   пакеты для nfqws2. В TUN inbound такой опции НЕТ.
  # - default_mark = 8227 — помечает все исходящие сокеты sing-box
  #   (для разрыва петли через TUN). Отдельная метка,
  #   НЕ связана с routing_mark = 110.
  # - stack = "gvisor" — КРИТИЧНО.
  # - IPv6-адрес на TUN УБРАН (ядро Linux отклоняет его при MTU 1280
  #   с ошибкой "invalid argument"). У нас нет рабочего IPv6
  #   от провайдера, DNS не отдаёт AAAA-записи (block_ipv6 = true).
  # - MTU = 1300 — компромисс между:
  #     * минимумом для gvisor (~1280);
  #     * необходимостью, чтобы nfqws2 не получал пакеты 1480+,
  #       которые не влезают в raw socket.
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

          # address: только IPv4-префикс.
          # IPv6-адрес убран, потому что ядро отклоняет его на TUN
          # при MTU <= 1280 с ошибкой "invalid argument".
          address = [
            "172.19.0.1/30"
          ];

          # dns_mode = "disabled": sing-box НЕ перехватывает DNS.
          dns_mode = "disabled";

          auto_route = true;
          strict_route = false;

          # MTU TUN-интерфейса.
          # 1300 — компромисс:
          #   * > 1280 (минимум для gvisor);
          #   * < 1400, чтобы пакеты, которые nfqws2 отправляет
          #     через raw socket, не превышали MTU физического
          #     интерфейса (1500) с учётом накладных расходов.
          mtu = 1300;

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
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }
          # ---------------------------------------------------------
          # X.com / Twitter:
          # 1. reject QUIC (UDP/443) → Brave уходит на TCP.
          #    blockcheck показал, что TCP X.com работает без обхода,
          #    а QUIC — блокируется. Без этого правила Brave висит
          #    на HTTP/3, и X.com не открывается.
          # 2. TCP X.com → direct-out (не через nfqws2 — там он не
          #    нужен, стратегия не найдена и мешает).
          # ---------------------------------------------------------
          {
            domain_suffix = [
              ".x.com"
              ".twitter.com"
              ".t.co"
              ".twimg.com"
            ];
            network = "udp";
            port = [443];
            action = "reject";
          }
          {
            domain_suffix = [
              ".x.com"
              ".twitter.com"
              ".t.co"
              ".twimg.com"
            ];
            outbound = "direct-out";
          }
          # ---------------------------------------------------------
          # Fallback: всё остальное → zapret-out (через nfqws2).
          # Здесь YouTube и прочие SNI-blocked домены.
          # ---------------------------------------------------------
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
