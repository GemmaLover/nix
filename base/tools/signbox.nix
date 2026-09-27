{ config, lib, pkgs, ... }:

{
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
          strict_route = true;
        }
      ];

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

      dns = {
        servers = [
          {
            type = "udp";
            tag = "dns-dnscrypt";
            server = "127.0.0.1";
            server_port = 5353;
          }
        ];
        rules = [ { server = "dns-dnscrypt"; } ];
        disable_cache = false;
      };

      route = {
        find_process = true;
        auto_detect_interface = true;

        rules = [
          # 1. Сниффинг.
          { action = "sniff"; }

          # 2. dnscrypt-proxy идёт напрямую, минуя hijack-dns.
          # Без этого правила sing-box перехватывает исходящие запросы
          # dnscrypt-proxy к Cloudflare/Quad9 и заворачивает их обратно,
          # создавая петлю и таймауты на старте.
          { process_name = [ "dnscrypt-proxy" ]; outbound = "direct-out"; }

          # 3. Перехватывать DNS от остальных процессов.
          { protocol = "dns"; action = "hijack-dns"; }

          # 4. Loopback — напрямую.
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 5. Brave → SOCKS5.
          { process_name = [ "brave" ]; outbound = "socks-out"; }
          { process_path_regex = [ ".*/brave/brave.*" ]; outbound = "socks-out"; }

          # 6. Chromium → VLESS.
          { process_name = [ "chromium" ]; outbound = "vless-out"; }
          { process_path_regex = [ ".*/chromium/chromium.*" ]; outbound = "vless-out"; }

          # 7. Всё остальное → direct.
          { outbound = "direct-out"; }
        ];
      };


    };
  };

  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw,cap_sys_ptrace+ep";
    owner = "root";
    group = "root";
  };
}
