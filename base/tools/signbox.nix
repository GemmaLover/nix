{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация трафика по процессам.
  #
  # Режим: TUN. Перехватывает весь IP-трафик системы на уровне ядра,
  # включая трафик Flatpak-приложений.
  #
  # Логика маршрутизации:
  #   - Brave (Flatpak)     → SOCKS5 (chelik / pass11)
  #   - Chromium (Flatpak)  → VLESS
  #   - Всё остальное       → direct (напрямую)
  #
  # ВАЖНО: для работы TUN нужны права CAP_NET_ADMIN и CAP_NET_RAW.
  # Они выдаются через security.wrappers ниже.
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      # --- Входящий интерфейс: TUN ---
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          # Адрес внутри TUN-подсети. Не должен конфликтовать с локальной сетью.
          address = [ "172.19.0.1/30" ];
          # Автоматически добавлять маршруты, чтобы весь трафик шёл в TUN.
          auto_route = true;
          # Строгая маршрутизация для избежания утечек.
          strict_route = true;
          # Анализ трафика для более точной маршрутизации.
          sniff = true;
        }
      ];

      # --- Исходящие подключения ---
      outbounds = [
        # 1. SOCKS5 — для Brave.
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";      # <-- ЗАМЕНИТЕ на адрес вашего SOCKS5-прокси
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
          flow = "xtls-rprx-vision"; # или другой, из вашего конфига
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН"; # <-- ЗАМЕНИТЕ
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }

        # 3. Direct — по умолчанию.
        {
          type = "direct";
          tag = "direct-out";
        }
      ];

      # --- Маршрутизация ---
      route = {
        # Обязательно для правил process_name / process_path.
        find_process = true;

        # Автоматически определять интерфейс для Direct-out.
        auto_detect_interface = true;

        rules = [
          # 1. Brave → SOCKS5.
          # Имя процесса у Flatpak-версии Brave — "brave".
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }

          # 2. Chromium → VLESS.
          # Имя процесса у Flatpak-версии Chromium — "chromium".
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }

          # 3. Всё остальное → direct.
          # Правило без условий (catch-all) должно быть последним.
          {
            outbound = "direct-out";
          }
        ];
      };
    };
  };

  # =====================================================================
  # Права для TUN-интерфейса.
  #
  # sing-box должен уметь создавать сетевой интерфейс и управлять
  # маршрутами. Без CAP_NET_ADMIN / CAP_NET_RAW TUN не поднимется.
  # =====================================================================
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw+ep";
    owner = "root";
    group = "root";
  };
}
