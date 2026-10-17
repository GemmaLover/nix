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
  #   * qt + programs.konsole   — тёмная тема и корректный профиль Konsole;
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

    # === window-rules для Konsole ===
    # По умолчанию Niri открывает одиночное окно в плиточном режиме
    # на всю доступную область — это не «полноэкранный режим», а
    # штатное поведение тайлинга. Правило ниже делает Konsole
    # плавающим окном при запуске, чтобы он не разворачивался.
    #
    # ВАЖНО: в niri-flake правило задаётся через `matches` (список
    # attrset'ов), а НЕ через `match` (attrset). Именно из-за `match`
    # nix flake check падал с «option does not exist. Did you mean
    # `matches`?».
    #
    # app-id Konsole обычно "konsole" (Wayland). Если правило не
    # сработает, уточните app-id командой:
    #   niri msg pick-window   (кликните по окну Konsole)
    window-rules = [
      {
        matches = [
          { app-id = "konsole"; }
        ];
        open-floating = true;
      }
    ];

    # === Биндинги ===
    binds = {
      # --- Терминал и файловый менеджер ---
      "Mod+T".action.spawn = "konsole";
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

  # =====================================================================
  # Konsole — профиль по умолчанию.
  #
  # Широкие отступы между буквами и артефакты по центру вызваны
  # включённым «Word Mode» (Complex Text Layout) в Konsole — это
  # известный баг рендеринга при определённых шрифтах и настройках
  # Qt/Plasma 6. Отключаем WordMode и явно задаём моноширинный шрифт.
  # =====================================================================
  programs.konsole = {
    enable = true;
    defaultProfile = "Default";

    profiles.Default = {
      font = {
        name = "DejaVu Sans Mono";
        size = 12;
      };

      # Отключаем Word Mode — главную причину широких отступов
      # между символами и артефактов рендеринга.
      extraConfig = {
        Appearance = {
          WordMode = false;
        };
      };
    };
  };

  # Переменные окружения — только то, что модуль qt НЕ выставляет.
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # === Пакеты ===
  home.packages = with pkgs; [
    kdePackages.konsole   # KDE-терминал
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
    dejavu_fonts          # DejaVu Sans Mono для Konsole
  ];
}
