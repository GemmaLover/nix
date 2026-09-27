{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box 1.14 — маршрутизация трафика по процессам.
  #
  # ВАЖНО: В sing-box 1.14.0 удалены устаревшие поля inbound:
  #   - sniff = true      → заменено на action: "sniff" в route.rules
  #   - stack = "system"  → убрано
  #
  # Также удалён старый формат DNS-серверов. Теперь нужно указывать
  # type (udp, tcp, tls, https) и server/server_port.
  #
  # Логика маршрутизации:
  #   - Brave (Flatpak)     → SOCKS5 (chelik / pass11)
  #   - Chromium (Flatpak)  → VLESS
  #   - Всё остальное       → direct-out
  #   - DNS                 → 127.0.0.1:5353 (dnscrypt-proxy)
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      # --- Логи ---
      log = { level = "info"; };

      # --- Входящий интерфейс: TUN ---
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

      # --- Исходящие подключения ---
      outbounds = [
        # 1. SOCKS5 — для Brave.
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";      # <-- ЗАМЕНИТЕ на адрес SOCKS5-прокси
          server_port = 1080;        # <-- ЗАМЕНИТЕ на порт
          version = "5";
          username = "chelik";
          password = "pass11";
        }

        # 2. VLESS — для Chromium.
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
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }

        # 3. Direct — по умолчанию.
        { type = "direct"; tag = "direct-out"; }
      ];

      # =====================================================================
      # DNS — новый формат для sing-box 1.14.
      #
      # Вместо старого "address" теперь используются:
      #   type: "udp" (или "tcp", "tls", "https")
      #   server: "127.0.0.1"
      #   server_port: 5353
      # =====================================================================
      dns = {
        servers = [
          {
            type = "udp";                # новый формат
            tag = "dns-dnscrypt";
            server = "127.0.0.1";
            server_port = 5353;
            # detour указывает, через какой outbound идти
            # к DNS-серверу. direct-out — напрямую.
            detour = "direct-out";
          }
        ];

        rules = [
          { server = "dns-dnscrypt"; }
        ];

        disable_cache = false;
        independent_cache = true;
      };

      # --- Маршрутизация ---
      route = {
        find_process = true;
        auto_detect_interface = true;

        rules = [
          # 0. Loopback — напрямую, минуя TUN.
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 1. Сниффинг (замена sniff = true из inbound).
          { action = "sniff"; }

          # 2. Brave (Flatpak) → SOCKS5.
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }

          # 3. Chromium (Flatpak) → VLESS.
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }

          # 4. Всё остальное → direct.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # Права для TUN и чтения информации о процессах.
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw,cap_sys_ptrace+ep";
    owner = "root";
    group = "root";
  };
}
