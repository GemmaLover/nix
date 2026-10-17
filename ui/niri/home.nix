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
    #
    # ВАЖНО: Mod+←/→ и Mod+↑/↓ в Niri по умолчанию заняты фокусом
    # (focus-column-left/right, focus-window-up/down). Ниже эти
    # комбинации переопределены под перемещение — так, как вы просили.
    # Если позже захотите вернуть фокус на стрелки, добавьте отдельные
    # биндинги, например Mod+H/J/K/L для фокуса.
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

      # ===============================================================
      # === НОВОЕ: перемещение окна/колонки в текущем пространстве ===
      # Mod+←/→ сдвигает активную колонку влево/вправо (меняет порядок
      # колонок на текущем рабочем пространстве).
      # ===============================================================
      "Mod+Left".action.move-column-left = { };
      "Mod+Right".action.move-column-right = { };

      # ===============================================================
      # === НОВОЕ: перемещение активного окна между пространствами ===
      # Mod+↑/↓ переносит активное окно на соседнее рабочее
      # пространство (вверх/вниз по вертикальной ленте). Если
      # следующего нет — Niri создаст новое.
      # focus = false — фокус остаётся на исходном пространстве:
      # вы «выносите» окно и продолжаете работу здесь.
      # Уберите focus = false, если хотите, чтобы фокус следовал.
      # ===============================================================
      "Mod+Up".action.move-window-to-workspace-up = { focus = false; };
      "Mod+Down".action.move-window-to-workspace-down = { focus = false; };

      # ===============================================================
      # === НОВОЕ: переключение на рабочее пространство по номеру ===
      # Индекс — позиция в вертикальной ленте на текущем мониторе.
      # Если такого индекса ещё нет, Niri переключится на нижнее
      # пустое пространство (и создаст его при необходимости).
      # ===============================================================
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;

      # ===============================================================
      # === Опционально: перенос окна сразу на номер 1..5 ===
      # Аналог «вынести окно на рабочий стол N». Раскомментируйте,
      # если нужно (иначе — просто Mod+↑/↓ шаг за шагом).
      # ===============================================================
      # "Mod+Shift+1".action.move-window-to-workspace = 1;
      # "Mod+Shift+2".action.move-window-to-workspace = 2;
      # "Mod+Shift+3".action.move-window-to-workspace = 3;
      # "Mod+Shift+4".action.move-window-to-workspace = 4;
      # "Mod+Shift+5".action.move-window-to-workspace = 5;

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
  # поэтому Git по умолчанию не может сохранить логин/пароль.
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

    # Git с поддержкой libsecret — иначе нет git-credential-libsecret.
    package = pkgs.git.override { withLibsecret = true; };

    settings = {
      user = {
        name = "lexi";
        email = "lexi@example.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;

      # credential helper — сохранение паролей в gnome-keyring.
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
  # force = true — Home Manager перезапишет уже существующий файл
  # (мог остаться от KDE), иначе активация падает с
  # «Existing file would be clobbered».
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
  # QT_QPA_PLATFORMTHEME и QT_STYLE_OVERRIDE задаются qt-модулем
  # автоматически (qt5ct / kvantum).
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # === Пакеты ===
  home.packages = with pkgs; [
    foot                  # Wayland-терминал
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
