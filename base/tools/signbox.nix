{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация трафика по процессам.
  #
  # ВАЖНО: используется sing-box 1.14.1, где удалены устаревшие поля.
  #   - sniff = true в inbound      → УДАЛЕНО, заменено на action: "sniff"
  #                                     в route.rules.
  #   - stack = "system" в inbound → deprecated, лучше убрать.
  #
  # Логика маршрутизации:
  #   - Brave (Flatpak)     → SOCKS5 (chelik / pass11)
  #   - Chromium (Flatpak)  → VLESS
  #   - Всё остальное       → direct (напрямую)
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      # --- Входящий интерфейс: TUN ---
      # УБРАНЫ поля sniff и stack — они больше не поддерживаются.
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
            server_name = "ВАШ_ДОМЕН";
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }

        # 3. Direct — по умолчанию.
        { type = "direct"; tag = "direct-out"; }
      ];

      # --- Маршрутизация ---
      route = {
        find_process = true;
        auto_detect_interface = true;

        rules = [
          # Первое правило: сниффинг трафика (замена sniff = true в inbound).
          # Без него маршрутизация по доменам не работает, но для
          # правил по process_name он не обязателен. Включаем для полноты.
          { action = "sniff"; timeout = "300ms"; }

          # 1. Brave (Flatpak) → SOCKS5.
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }

          # 2. Chromium (Flatpak) → VLESS.
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }

          # 3. Всё остальное → direct.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # Права для TUN-интерфейса.
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    capabilities = "cap_net_admin,cap_net_raw,cap_sys_ptrace+ep";
    owner = "root";
    group = "root";
  };
}
