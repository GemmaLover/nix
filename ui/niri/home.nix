{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/niri/home.nix — Home Manager-слой оси Niri.
  #
  # Подключается диспетчером devices/<host>/home-specific/default.nix
  # при kdaOpts.ui = "niri".
  #
  # Здесь — декларативная конфигурация:
  #   * programs.niri.settings  — биндинги, layout, window-rules,
  #     spawn-at-startup (генерирует ~/.config/niri/config.kdl);
  #   * programs.noctalia.*     — сам шелл и декларативное включение плагинов;
  #   * qt + programs.git       — тёмная тема и сохранение паролей Git;
  #   * базовые пакеты-аналоги KDE-компонентов.
  # =====================================================================

  programs.niri.settings = {
    # Noctalia запускается при старте сессии.
    spawn-at-startup = [
      { command = [ "noctalia-shell" ]; }
    ];

    # Раскладка клавиатуры: та же, что в base/system/keyboard.nix.
    input.keyboard.xkb = {
      layout = "us,ru";
      options = "grp:caps_toggle,caps:escape";
    };

    layout.gaps = 5;

    # === window-rules ===
    # В niri-flake правило задаётся через `matches` (список attrset'ов).
    # Если понадобится сделать какое-то приложение плавающим,
    # раскомментируйте шаблон ниже и замените app-id.
    #
    # window-rules = [
    #   {
    #     matches = [ { app-id = "some-app"; } ];
    #     open-floating = true;
    #   }
    # ];

    # === Биндинги ===
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

      # === Noctalia v5+ IPC ===
      "Mod+Space" = {
        action.spawn-sh = "noctalia msg panel-toggle launcher";
      };
      "Mod+Shift+Q" = {
        action.spawn-sh = "noctalia msg panel-toggle session";
      };
      "Mod+F1" = {
        action.spawn-sh = "noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet";
      };

      # === Перемещение окон в текущем рабочем пространстве ===
      "Mod+Shift+Left".action.move-column-left = { };
      "Mod+Shift+Right".action.move-column-right = { };
      "Mod+Shift+Up".action.move-window-up = { };
      "Mod+Shift+Down".action.move-window-down = { };

      # === Вынос окна в новое / соседнее рабочее пространство ===
      "Mod+Ctrl+Down".action.move-window-to-workspace-down = { focus = false; };
      "Mod+Ctrl+Up".action.move-window-to-workspace-up = { focus = false; };

      # --- Скриншоты ---
      "Print".action.screenshot = { };
      "Mod+Print".action.screenshot-window = { };
      "Mod+Shift+Print".action.screenshot-screen = { };
    };
  };

  # === Noctalia — Wayland-шелл ===
  programs.noctalia = {
    enable = true;
    systemd.enable = true;

    settings = {
      plugins = {
        enabled = [ "kenn/keybind-cheatsheet" ];
      };
    };
  };

  # =====================================================================
  # Git: сохранение паролей через libsecret (GNOME Keyring).
  #
  # В чистой Wayland-сессии (Niri) нет провайдера org.freedesktop.secrets,
  # поэтому Git по умолчанию не может сохранить логин/пароль. Konsole
  # работал только потому, что наследовал окружение KDE, где keyring
  # уже был разблокирован.
  #
  # Решение: собрать Git с поддержкой libsecret и указать
  # git-credential-libsecret как credential.helper. Пароли будут
  # сохраняться в gnome-keyring.
  #
  # ВАЖНО: сам gnome-keyring должен быть разблокирован при входе
  # через greetd — см. security.pam.services.greetd.enableGnomeKeyring
  # в ui/niri/niri.nix.
  # =====================================================================
  programs.git = {
    enable = true;

    # === НОВОЕ: Git с поддержкой libsecret ===
    # Без withLibsecret в бинарнике нет git-credential-libsecret.
    package = pkgs.git.override { withLibsecret = true; };

    settings = {
      user = {
        name = "lexi";
        email = "lexi@example.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;

      # === НОВОЕ: credential helper ===
      # Указывает Git использовать libsecret для сохранения паролей.
      # Путь берётся из того же пакета, что и programs.git.package.
      credential.helper = "${pkgs.git.override { withLibsecret = true; }}/bin/git-credential-libsecret";
    };
  };

  # =====================================================================
  # Тёмная тема для Qt/KDE-приложений.
  # =====================================================================
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";

    kvantum = {
      enable = true;
      settings = {
        General = {
          theme = "KvFlat";
          composite = false;
          iconless_pushbutton = true;
        };
      };
    };
  };

  # kdeglobals: цветовая схема KDE-приложений (BreezeDark).
  xdg.configFile."kdeglobals" = {
    force = true;
    text = ''
      [General]
      ColorScheme=BreezeDark
      Name=Breeze Dark
      shadeSortColumn=true

      [KDE]
      widgetStyle=Breeze
      contrast=4

      [UiSettings]
      ColorScheme=qt6ct

      [Colors:Window]
      BackgroundNormal=35,38,41
      ForegroundNormal=239,240,241
      BackgroundInactive=35,38,41
      ForegroundInactive=189,195,199
      BackgroundActive=35,38,41
      ForegroundActive=61,174,233
      ForegroundLink=41,128,185
      ForegroundVisited=127,140,141
      ForegroundNegative=218,68,83
      ForegroundNeutral=246,116,0
      ForegroundPositive=17,209,22

      [Colors:View]
      BackgroundNormal=27,30,32
      ForegroundNormal=239,240,241
      BackgroundInactive=27,30,32
      ForegroundInactive=189,195,199
      BackgroundActive=27,30,32
      ForegroundActive=61,174,233

      [Colors:Button]
      BackgroundNormal=42,46,50
      ForegroundNormal=239,240,241
      BackgroundInactive=42,46,50
      ForegroundInactive=189,195,199
      BackgroundActive=42,46,50
      ForegroundActive=61,174,233
    '';
  };

  # Переменные окружения — только то, что модуль qt НЕ выставляет.
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # === Пакеты ===
  home.packages = with pkgs; [
    foot                  # Wayland-терминал (возвращён)
    wofi                  # standalone-лаунчер
    kdePackages.dolphin   # файловый менеджер

    # --- Тёмная тема Qt/KDE ---
    kdePackages.qt6ct
    qt6Packages.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.breeze
    kdePackages.breeze-icons
    kdePackages.plasma-integration
    adwaita-icon-theme

    # --- Git: libsecret для сохранения паролей ---
    libsecret             # библиотека Secret Service
    gnome-keyring         # провайдер org.freedesktop.secrets
  ];
}
