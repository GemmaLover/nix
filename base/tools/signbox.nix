{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация трафика по процессам.
  #
  # Конфигурация для sing-box 1.14 (nixpkgs-unstable).
  # ВАЖНО: в 1.13+ удалены устаревшие поля inbound:
  #   - sniff = true      → заменено на action: "sniff" в route.rules
  #   - stack = "system"  → убрано
  #
  # Логика маршрутизации:
  #   - Brave (Flatpak)     → SOCKS5 (chelik / pass11)
  #   - Chromium (Flatpak)  → VLESS
  #   - Всё остальное       → direct-out
  #   - DNS                 → 127.0.0.1:5353 (dnscrypt-proxy)
  #
  # DNS-запросы перехватываются через TUN и передаются локальному
  # dnscrypt-proxy, который шифрует их (DoH/DNSCrypt) и отправляет
  # на upstream (Cloudflare, Quad9, Scaleway).
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      # --- Логи ---
      # info даёт достаточно данных для отладки маршрутизации,
      # но не забивает журнал (в отличие от debug/trace).
      log = { level = "info"; };

      # --- Входящий интерфейс: TUN ---
      # Захватывает весь IP-трафик системы на уровне ядра,
      # включая трафик Flatpak-приложений.
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          # Адрес внутри TUN-подсети. Не должен конфликтовать
          # с локальной сетью (192.168.x.x).
          address = [ "172.19.0.1/30" ];
          # Автоматически добавлять маршруты через TUN.
          auto_route = true;
          # Строгая маршрутизация — предотвращает утечки
          # трафика в обход прокси.
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
      # DNS — через локальный dnscrypt-proxy на 127.0.0.1:5353.
      #
      # sing-box сам перехватывает DNS-запросы через TUN и передаёт
      # их dnscrypt-proxy. Тот шифрует (DoH/DNSCrypt) и отправляет
      # на upstream. Portmaster (127.0.0.17:53) в этой цепочке
      # не участвует — sing-box перехватывает запросы раньше.
      # =====================================================================
      dns = {
        servers = [
          {
            tag = "dns-dnscrypt";
            # dnscrypt-proxy слушает и UDP, и TCP на 127.0.0.1:5353.
            address = "127.0.0.1";
            address_port = 5353;
            # IP-адрес, а не домен — резолвер не нужен.
            address_resolver = "";
            # detour = "direct-out" — обращение к dnscrypt идёт
            # напрямую, без прокси. Loopback исключён из TUN
            # правилом ниже, поэтому петли не будет.
            detour = "direct-out";
            strategy = "prefer_ipv4";
          }
        ];

        rules = [
          # Все DNS-запросы → dnscrypt-proxy.
          { server = "dns-dnscrypt"; }
        ];

        disable_cache = false;
        independent_cache = true;
      };

      # --- Маршрутизация ---
      route = {
        # Обязательно для правил process_name / process_path_regex.
        # Без этого sing-box не знает, какому процессу принадлежит
        # соединение.
        find_process = true;

        # Автоматически определять интерфейс для direct-out.
        auto_detect_interface = true;

        rules = [
          # 0. Loopback — напрямую, минуя TUN.
          # Нужно, чтобы DNS-запросы к dnscrypt-proxy (127.0.0.1:5353)
          # не заворачивались обратно в sing-box (иначе петля).
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 1. Сниффинг доменов (замена sniff = true из inbound).
          # Позволяет маршрутизировать по домену, а не только по IP.
          { action = "sniff"; timeout = "300ms"; }

          # 2. Brave (Flatpak) → SOCKS5.
          # Имя процесса у Flatpak-версии Brave — "brave".
          # process_path_regex ловит процессы по пути — страховка
          # на случай, если find_process вернёт bwrap/zypak.
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

          # 4. Всё остальное → direct-out.
          # Это правило должно быть ПОСЛЕДНИМ — оно catch-all.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # =====================================================================
  # Права для TUN-интерфейса и чтения информации о процессах.
  #
  #   cap_net_admin — создание сетевого интерфейса и маршрутов.
  #   cap_net_raw   — работа с сырыми сокетами.
  #   cap_sys_ptrace — чтение /proc/<pid>/exe для определения
  #                    пути процесса (нужно для process_path_regex).
  # =====================================================================
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw,cap_sys_ptrace+ep";
    owner = "root";
    group = "root";
  };
}
