{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/niri/home.nix — Home Manager-слой оси Niri.
  #
  # Подключается диспетчером devices/<host>/home-specific/default.nix
  # при kdaOpts.ui = "niri".
  #
  # Здесь — декларативная конфигурация:
  #   * programs.niri.settings  — биндинги, layout, spawn-at-startup
  #     (генерирует ~/.config/niri/config.kdl через niri-flake HM-модуль);
  #   * programs.noctalia.*     — сам шелл (панель, лаунчер, уведомления);
  #   * базовые пакеты-аналоги KDE-компонентов:
  #       Konsole    -> foot (Wayland-терминал)
  #       Kickoff    -> wofi (standalone-лаунчер; Noctalia также имеет
  #                     свой, но wofi удобно держать отдельно)
  #       Dolphin    -> kdePackages.dolphin (Qt6/Wayland, работает нативно)
  #       Spectacle  -> встроенные screenshot-биндинги Niri
  # =====================================================================

  programs.niri.settings = {
    # Noctalia запускается при старте сессии.
    spawn-at-startup = [
      { command = [ "noctalia-shell" ]; }
    ];

    # Раскладка клавиатуры: та же, что в base/system/keyboard.nix
    # (US/RU, переключение по CapsLock, CapsLock также = Escape).
    input.keyboard.xkb = {
      layout = "us,ru";
      options = "grp:caps_toggle,caps:escape";
    };

    # Базовый layout: зазоры между окнами.
    layout.gaps = 5;

    # === Биндинги ===
    # Mod — это Super (Windows). Стандартные для Niri:
    #   Mod+T       — терминал (foot)
    #   Mod+Q       — закрыть окно
    #   Mod+E       — файловый менеджер (Dolphin)
    #   Mod+D       — standalone-лаунчер (wofi)
    #   Mod+Space   — лаунчер Noctalia (v5+ IPC)
    #   Mod+Shift+Q — меню питания Noctalia (v5+ IPC)
    #   Mod+/       — шпаргалка Noctalia (v5+ IPC)
    #   Mod+Shift+L — заблокировать сессию
    #   Mod+Shift+E — выйти из Niri
    binds = {
      # --- Терминал и файловый менеджер ---
      "Mod+T".action.spawn = "foot";
      "Mod+E".action.spawn = "dolphin";

      # --- Окна ---
      "Mod+Q".action.close-window = { };
      "Mod+D".action.spawn = "wofi --show drun";

      # --- Сессия ---
      "Mod+Shift+L".action.spawn = "loginctl lock-session";
      "Mod+Shift+E".action.quit = { };

      # === Noctalia v5+ IPC (исправленный синтаксис) ===
      # В Noctalia v5+ команды вызываются через `noctalia msg ...`,
      # а НЕ через старый `noctalia-shell ipc call ...`.
      # Если команда не срабатывает — проверьте `noctalia msg --help`.

      # Лаунчер приложений Noctalia.
      "Mod+Space" = {
        action.spawn-sh = "noctalia msg panel-toggle launcher";
      };
      # Меню выключения/перезагрузки/выхода.
      "Mod+Shift+Q" = {
        action.spawn-sh = "noctalia msg panel-toggle session";
      };
      # Шпаргалка по клавишам (плагин keybind-cheatsheet в Noctalia).
      # В Niri символ '/' называется `slash`.
      "Mod+slash" = {
        action.spawn-sh = "noctalia msg cheatsheet-toggle";
      };

      # --- Скриншоты (встроенные в Niri, аналог Spectacle) ---
      "Print".action.screenshot = { };
      "Mod+Print".action.screenshot-window = { };
      "Mod+Shift+Print".action.screenshot-screen = { };
    };
  };

  # === Noctalia — Wayland-шелл ===
  # Включает systemd user service и регистрирует автозапуск.
  # Программный запуск уже прописан в spawn-at-startup выше.
  # Дополнительные настройки (тема, расположение панели) добавляйте
  # в programs.noctalia.settings по мере необходимости — схема
  # соответствует TOML-конфигу Noctalia.
  #
  # ВАЖНО: systemd.enable = true привязывает сервис к
  # graphical-session.target, который активен и в Plasma, и в Niri.
  # Пока ui = "niri" — это нормально. Если временно вернётесь на KDE,
  # поставьте systemd.enable = false, чтобы Noctalia не запускался
  # поверх Plasma.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
  };

  # === Пакеты, которые нужны для базового workflow ===
  home.packages = with pkgs; [
    foot                  # Wayland-терминал (аналог Konsole)
    wofi                  # standalone-лаунчер (аналог Kickoff)
    kdePackages.dolphin   # файловый менеджер (Qt6/Wayland, привычный UI)
  ];
}
