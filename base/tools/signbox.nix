{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация трафика по процессам.
  #
  # DNS-фильтрацией занимается Portmaster (127.0.0.17:53), а резолвингом
  # dnscrypt-proxy (127.0.0.1:53). sing-box НЕ перехватывает DNS и
  # НЕ резолвит имена — он только распределяет TCP-трафик по прокси.
  #
  # Правила:
  #   - dnscrypt-proxy   → direct (DoH/DNSCrypt уже зашифрован)
  #   - portmaster-core  → direct (сам управляет nfqueue)
  #   - Brave (Flatpak)  → SOCKS5
  #   - Chromium         → VLESS
  #   - Всё остальное    → direct
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      log = { level = "info"; };

      # --- TUN ---
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          address = [ "172.19.0.1/30" ];
          auto_route = true;
          strict_route = true;
        }
      ];

      # --- Исходящие ---
      outbounds = [
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";      # <-- ЗАМЕНИТЕ
          server_port = 1080;        # <-- ЗАМЕНИТЕ
          version = "5";
          username = "chelik";
          password = "pass11";
        }
        {
          type = "vless";
          tag = "vless-out";
          server = "ВАШ_СЕРВЕР";     # <-- ЗАМЕНИТЕ
          server_port = 443;         # <-- ЗАМЕНИТЕ
          uuid = "ВАШ_UUID";         # <-- ЗАМЕНИТЕ
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН";  # <-- ЗАМЕНИТЕ
            utls = { enabled = true; fingerprint = "chrome"; };
          };
        }
        { type = "direct"; tag = "direct-out"; }
      ];

      # DNS-секции НЕТ. sing-box не резолвит имена.

      # --- Маршрутизация ---
      route = {
        find_process = true;
        auto_detect_interface = true;

        rules = [
          # 1. Loopback (127.0.0.0/8, ::1/128) — direct.
          # Покрывает обращения к dnscrypt (127.0.0.1:53),
          # Portmaster (127.0.0.17:53) и любым локальным сервисам.
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 2. dnscrypt-proxy — direct.
          # Его исходящие — это DoH/DNSCrypt, уже зашифрованные.
          # sing-box не должен их трогать.
          {
            process_name = [ "dnscrypt-proxy" ];
            outbound = "direct-out";
          }

          # 3. Portmaster — direct.
          # Он сам перехватывает DNS через nfqueue и фильтрует.
          {
            process_name = [ "portmaster-core" ];
            outbound = "direct-out";
          }

          # 4. Сниффинг доменов (для возможной маршрутизации по домену).
          { action = "sniff"; }

          # 5. Brave (Flatpak) → SOCKS5.
          { process_name = [ "brave" ]; outbound = "socks-out"; }
          { process_path_regex = [ ".*/brave/brave.*" ]; outbound = "socks-out"; }

          # 6. Chromium (Flatpak) → VLESS.
          { process_name = [ "chromium" ]; outbound = "vless-out"; }
          { process_path_regex = [ ".*/chromium/chromium.*" ]; outbound = "vless-out"; }

          # 7. Всё остальное → direct.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # Права для TUN и чтения процессов.
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
  };
}
