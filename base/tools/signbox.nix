{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box 1.14 — маршрутизация трафика по процессам.
  #
  # Особенности версии 1.14:
  #   - Удалены legacy inbound-поля (sniff, stack).
  #   - Новый формат DNS-серверов: type/server/server_port.
  #   - detour к пустому direct outbound не работает — DNS
  #     направляется через route.rules.
  #   - independent_cache удалён — не используем.
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
        # SOCKS5 — для Brave.
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";      # <-- ЗАМЕНИТЕ
          server_port = 1080;        # <-- ЗАМЕНИТЕ
          version = "5";
          username = "chelik";
          password = "pass11";
        }

        # VLESS — для Chromium.
        {
          type = "vless";
          tag = "vless-out";
          server = "ВАШ_СЕРВЕР";     # <-- ЗАМЕНИТЕ
          server_port = 443;         # <-- ЗАМЕНИТЕ
          uuid = "ВАШ_UUID";         # <-- ЗАМЕНИТЕ
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН";
            utls = { enabled = true; fingerprint = "chrome"; };
          };
        }

        # Direct — по умолчанию.
        { type = "direct"; tag = "direct-out"; }
      ];

      # --- DNS ---
      # Новый формат для sing-box 1.14: type + server + server_port.
      # detour НЕ указываем — DNS пойдёт по route.rules ниже.
      dns = {
        servers = [
          {
            type = "udp";
            tag = "dns-dnscrypt";
            server = "127.0.0.1";
            server_port = 5353;
          }
        ];

        rules = [
          { server = "dns-dnscrypt"; }
        ];

        disable_cache = false;
      };

      # --- Маршрутизация ---
      route = {
        find_process = true;
        auto_detect_interface = true;

        rules = [
          # 0. DNS к dnscrypt-proxy (127.0.0.1:5353) — напрямую.
          # Это правило идёт первым, чтобы DNS не ушёл в socks/vless.
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            port = [ 5353 ];
            outbound = "direct-out";
          }

          # 1. Прочий loopback — напрямую.
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 2. Сниффинг доменов (замена sniff=true из inbound).
          { action = "sniff"; }

          # 3. Brave → SOCKS5.
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }

          # 4. Chromium → VLESS.
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }

          # 5. Всё остальное → direct.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # Права для TUN и чтения процессов.
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw,cap_sys_ptrace+ep";
    owner = "root";
    group = "root";
  };
}
