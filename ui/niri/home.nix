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
    #   Mod+Return  — терминал (у нас Mod+T)
    #   Mod+Q       — закрыть окно
    #   Mod+Shift+E — выйти из Niri
    #   Mod+D       — лаунчер
    #   Mod+Shift+L — заблокировать сессию
    binds = {
      "Mod+T".action.spawn = "foot";
      "Mod+Q".action.close-window = { };
      "Mod+D".action.spawn = "wofi --show drun";
      "Mod+Shift+L".action.spawn = "loginctl lock-session";
      "Mod+Shift+E".action.quit = { };

      # Скриншоты (встроенные в Niri, аналог Spectacle):
      #   Print              — весь экран
      #   Mod+Print          — окно
      #   Mod+Shift+Print    — экран (через встроенный механизм)
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
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
  };

  # === Пакеты, которые нужны для базового workflow ===
  home.packages = with pkgs; [
    foot   # Wayland-терминал (аналог Konsole)
    wofi   # standalone-лаунчер (аналог Kickoff)
  ];
}
