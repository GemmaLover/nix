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
  #   * мультимедийные клавиши  — звук, яркость, медиа (Niri не делает это сам);
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

    # =================================================================
    # === Layout: обводка и фокус ===
    # =================================================================
    layout = {
      # Отступы между окнами.
      gaps = 3;

      # === НОВОЕ: отключаем стандартный focus-ring ===
      # Именно focus-ring по умолчанию рисует синюю прямоугольную
      # обводку вокруг активного окна. Отключаем его, чтобы
      # использовать border (он корректно сочетается со скруглением).
      focus-ring.enable = false;

      # === НОВОЕ: border для индикации активного окна ===
      border = {
        enable = true;
        # Толщина обводки. 2 — заметно, но не слишком толсто.
        width = 1;
        # Светло-серый цвет для активного окна.
        active.color = "#707070";
        # Полностью прозрачный цвет для неактивных окон:
        # обводка не рисуется, когда фокус на другом окне.
        inactive.color = "#00000000";
      };

      # === НОВОЕ: пресеты ширины колонок для Mod+X ===
      # Niri циклически переключает ширину активной колонки
      # между этими пропорциями. 0.5 даёт «половину экрана» —
      # именно этот preset используется, когда нужно поделить экран
      # пополам с двумя приложениями.
      preset-column-widths = [
        { proportion = 0.33333; }
        { proportion = 0.5; }
        { proportion = 0.66667; }
      ];
    };

    # === window-rules ===
    # В niri-flake правило задаётся через `matches` (список attrset'ов).
    # === НОВОЕ: правило для скругления всех окон ===
    # ВАЖНО: в niri-flake `geometry-corner-radius` — это submodule
    # (attrset с полями top-left/top-right/bottom-left/bottom-right),
    # а НЕ одно число, как в KDL-конфиге Niri. Если передать число,
    # nix flake check падает с ошибкой «not of type null or (submodule)».
    # Значения должны быть float (с .0).
    window-rules = [
      {
        # matches не указываем — правило применяется ко всем окнам.
        # Если нужно ограничить конкретным приложением, добавьте:
        #   matches = [ { app-id = "some-app"; } ];
        geometry-corner-radius = {
          top-left = 5.0;
          top-right = 5.0;
          bottom-left = 5.0;
          bottom-right = 5.0;
        };
        # Обрезать содержимое окна по скруглённым углам,
        # чтобы обводка и фон не «вылезали» за пределы.
        clip-to-geometry = true;
      }
    ];

    # === Биндинги ===
    #
    # Раскладка хоткеев переработана под запрос:
    #   * фокус окон — Mod+A / Mod+D
    #   * переключение рабочих пространств — Mod+W / Mod+S
    #   * размер активного окна — Mod+стрелки
    #   * перемещение окна/колонки — Mod+Shift+A / Mod+Shift+D
    #   * перенос окна между пространствами — Mod+Shift+W / Mod+Shift+S
    #
    # ВАЖНО: в Niri по умолчанию Mod+стрелки заняты фокусом
    # (focus-column-left/right, focus-window-up/down). Здесь они
    # переопределены под изменение размера — так, как вы просили.
    # Фокус переехал на Mod+A/D.
    binds = {
      # ================================================================
      # === Скриншоты ===
      # F6 (работает как Fn+F6) на этом железе отправляет KEY_S и НЕ
      # переназначается через keyd/evremap (известное ограничение
      # WMI-устройств ASUS, issue #1181). Поэтому биндинги на "Print"
      # и "Mod+Print" убраны — они всё равно не сработают.
      # Если понадобится скриншот, добавьте, например:
      #   "Mod+Shift+P".action.spawn-sh = "noctalia msg screenshot-region";
      # ================================================================

      # ================================================================
      # === Рабочие пространства ===
      # ================================================================

      # Переключение на рабочее пространство по номеру.
      # Индекс — позиция в вертикальной ленте на текущем мониторе.
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+6".action.focus-workspace = 6;

      # Перенос активного окна сразу на указанное пространство.
      "Mod+Shift+1".action.move-window-to-workspace = 1;
      "Mod+Shift+2".action.move-window-to-workspace = 2;
      "Mod+Shift+3".action.move-window-to-workspace = 3;
      "Mod+Shift+4".action.move-window-to-workspace = 4;
      "Mod+Shift+5".action.move-window-to-workspace = 5;
      "Mod+Shift+6".action.move-window-to-workspace = 6;

      # Переключение на предыдущее / следующее пространство.
      "Mod+W".action.focus-workspace-up = { };
      "Mod+S".action.focus-workspace-down = { };

      # ================================================================
      # === Фокус окон ===
      # Niri — колоночный WM: фокус переключается между колонками,
      # а не между окнами внутри колонки.
      # ================================================================
      "Mod+A".action.focus-column-left = { };
      "Mod+D".action.focus-column-right = { };

      # ================================================================
      # === Режимы отображения окна ===
      # ================================================================

      # Mod+Z — «растянуть» активную колонку на максимум (maximize-column).
      # Это не полноэкранный режим поверх других окон: колонка
      # растягивается до краёв экрана с сохранением отступов (gaps).
      "Mod+Z".action.maximize-column = { };

      # Mod+X — переключить ширину активной колонки по пресетам
      # (1/3 → 1/2 → 2/3, см. layout.preset-column-widths).
      # Чтобы «поделить экран пополам»: откройте первое приложение,
      # доведите его Mod+X до 1/2, затем откройте второе — оно встанет
      # в соседнюю колонку, тоже по 1/2.
      "Mod+X".action.switch-preset-column-width = { };

      # Mod+C — вынуть активное окно из тайлинга / вернуть обратно.
      # В Niri нет режима «4 угла» (это не сеточный WM), но плавающий
      # режим позволяет расположить окно вручную перетаскиванием.
      "Mod+C".action.toggle-window-floating = { };

      # ================================================================
      # === Изменение размера активного окна ===
      # Горизонталь — ширина колонки (set-column-width).
      # Вертикаль — высота окна внутри колонки (set-window-height).
      # Шаг 5% — если покажется медленно, замените на ±10%.
      # ================================================================
      "Mod+Left".action.set-column-width = "-5%";
      "Mod+Right".action.set-column-width = "+5%";
      "Mod+Up".action.set-window-height = "-5%";
      "Mod+Down".action.set-window-height = "+5%";

      # ================================================================
      # === Перемещение активного окна/колонки ===
      # Mod+Shift+A/D — сдвинуть колонку влево/вправо
      # (меняет порядок колонок на текущем пространстве).
      # Mod+Shift+W/S — перенести активное окно на пространство
      # выше/ниже. focus = false — фокус остаётся на исходном
      # пространстве (вы «выносите» окно и продолжаете работу здесь).
      # ================================================================
      "Mod+Shift+A".action.move-column-left = { };
      "Mod+Shift+D".action.move-column-right = { };
      "Mod+Shift+W".action.move-window-to-workspace-up = { focus = false; };
      "Mod+Shift+S".action.move-window-to-workspace-down = { focus = false; };

      # ================================================================
      # === Управление окнами и сессией ===
      # ================================================================
      "Mod+Q".action.close-window = { };
      "Mod+Shift+L".action.spawn = "loginctl lock-session";
      "Mod+Shift+E".action.quit = { };

      # ================================================================
      # === Noctalia v5+ IPC ===
      # ================================================================
      # Mod+Space — лаунчер приложений.
      "Mod+Space" = {
        action.spawn-sh = "noctalia msg panel-toggle launcher";
      };
      # Mod+Shift+Q — меню сессии (выключение/перезагрузка/выход).
      "Mod+Shift+Q" = {
        action.spawn-sh = "noctalia msg panel-toggle session";
      };
      # Mod+N — центр уведомлений (control-center).
      "Mod+N" = {
        action.spawn-sh = "noctalia msg panel-toggle control-center";
      };
      # Mod+Shift+K — важные горячие клавиши (шпаргалка keybind-cheatsheet).
      "Mod+Shift+K" = {
        action.spawn-sh = "noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet";
      };

      # ================================================================
      # === Запуск приложений ===
      # ================================================================
      "Mod+T".action.spawn = "foot";            # терминал
      "Mod+F".action.spawn = "firefox";         # браузер
      "Mod+R".action.spawn = "dolphin";         # файловый менеджер
      "Mod+E".action.spawn = "kate";            # текстовый редактор
      "Mod+K".action.spawn = "keepassxc";       # менеджер паролей
      "Mod+L".action.spawn = "llama-rocm-start";  # llama.cpp ROCm
      "Mod+P".action.spawn = "aimp";            # AIMP
      "Mod+U".action.spawn = "unsloth-start";   # Unsloth Studio
      # DSH: локальный вариант — dsh-local-start
      # (см. llm/dsh/local/commands.nix). Контейнерный —
      # dsh-podman-start, когда он появится.
      "Mod+H".action.spawn = "dsh-local-start";
      "Mod+M".action.spawn = "waydroid";        # Waydroid UI
      "Mod+I".action.spawn = "strata-start";    # Strata

      # ================================================================
      # === Мультимедийные клавиши (F1-F4, F7-F12 — XF86) ===
      # Niri не обрабатывает XF86-события сам — привязываем вручную.
      # wpctl — часть WirePlumber, brightnessctl — яркость,
      # playerctl — MPRIS-медиа. Все три пакета — в home.packages.
      #
      # ВАЖНО: используется action.spawn-sh (shell), а не action.spawn:
      # spawn НЕ выполняет команды через shell и не понимает `;`.
      # ================================================================

      # Громкость.
      # raise-volume сначала снимает mute (как plasma-pa в KDE),
      # иначе при [MUTED] set-volume поднимает громкость без звука.
      "XF86AudioRaiseVolume".action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
      "XF86AudioLowerVolume".action.spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      "XF86AudioMute".action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";

      # Микрофон.
      "XF86AudioMicMute".action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";

      # Яркость экрана.
      "XF86MonBrightnessUp".action.spawn-sh = "brightnessctl set 10%+";
      "XF86MonBrightnessDown".action.spawn-sh = "brightnessctl set 10%-";

      # Медиа-плеер (play/pause, next, prev) — работает в любом
      # MPRIS-совместимом плеере (VLC, mpv, Firefox и т.д.).
      "XF86AudioPlay".action.spawn-sh = "playerctl play-pause";
      "XF86AudioNext".action.spawn-sh = "playerctl next";
      "XF86AudioPrev".action.spawn-sh = "playerctl previous";
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

    # --- Мультимедийные утилиты для F1-F12 ---
    # wireplumber даёт команду wpctl (громкость).
    # brightnessctl — управление подсветкой экрана.
    # playerctl — MPRIS-медиа-клавиши (play/pause/next/prev).
    wireplumber
    brightnessctl
    playerctl
  ];
}
