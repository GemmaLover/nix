{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация TCP-трафика по процессам.
  #
  # Модель трафика (кто чем занимается):
  #   ┌─────────────────────────────────────────────────────────────┐
  #   │ Portmaster (127.0.0.17:53)                                  │
  #   │   - перехватывает DNS через nfqueue                         │
  #   │   - фильтрует и форвардит на dnscrypt-proxy                 │
  #   ├─────────────────────────────────────────────────────────────┤
  #   │ dnscrypt-proxy (127.0.0.1:53 и :5353)                       │
  #   │   - шифрует DNS (DoH/DNSCrypt) → Cloudflare/Quad9/Scaleway  │
  #   ├─────────────────────────────────────────────────────────────┤
  #   │ sing-box (TUN singtun0)                                     │
  #   │   - DNS НЕ трогает                                          │
  #   │   - dnscrypt-proxy → direct                                 │
  #   │   - portmaster-core → direct                                │
  #   │   - Brave → SOCKS5, Chromium → VLESS                        │
  #   │   - Firefox, nix, всё остальное → direct                    │
  #   └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  #   - DNS-секции нет. sing-box не резолвит имена.
  #   - default_mark = 8227 — помечает исходящие сокеты sing-box.
  #     Требуется правило ip rule, которое создаёт
  #     сервис sing-box-fwmark-rule (см. ниже).
  #   - MTU = 1400, strict_route = false.
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      log = { level = "info"; };

      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          address = [ "172.19.0.1/30" ];
          auto_route = true;
          strict_route = false;
          mtu = 1400;
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
            utls = { enabled = true; fingerprint = "chrome"; };
          };
        }
        { type = "direct"; tag = "direct-out"; }
      ];

      route = {
        find_process = true;
        auto_detect_interface = true;

        # Помечаем исходящие socket'ы sing-box fwmark 8227 (0x2023).
        # Правило ip rule для этого mark создаётся сервисом
        # sing-box-fwmark-rule ниже.
        default_mark = 8227;

        rules = [
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }
          {
            process_name = [ "dnscrypt-proxy" ];
            outbound = "direct-out";
          }
          {
            process_name = [ "portmaster-core" ];
            outbound = "direct-out";
          }
          { action = "sniff"; }
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }
          { outbound = "direct-out"; }
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
    path = [ pkgs.nftables pkgs.iptables pkgs.iproute2 ];
  };

  # =====================================================================
  # Правило маршрутизации для fwmark 8227.
  #
  # sing-box с default_mark = 8227 помечает свои исходящие сокеты
  # этим fwmark, но НЕ создаёт ip rule автоматически.
  #
  # priority 100 — выше правил auto_route (9000-9010),
  # поэтому срабатывает раньше и выводит пакеты sing-box
  # из петли через TUN.
  # =====================================================================
  systemd.services.sing-box-fwmark-rule = {
    description = "Add ip rule for sing-box default_mark (break TUN loop)";
    wantedBy = [ "multi-user.target" ];
    after = [ "sing-box.service" ];
    requires = [ "sing-box.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip rule add fwmark 8227 lookup main priority 100";
      ExecStop = "${pkgs.iproute2}/bin/ip rule del fwmark 8227 lookup main priority 100";
    };
  };
}
