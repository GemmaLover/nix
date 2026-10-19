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
  #
  # ШРИФТЫ:
  #   * JetBrains Mono (Nerd Font) — единственный кастомный шрифт,
  #     используется везде: sans-serif, monospace, GTK, Qt, foot.
  #   * Montserrat удалён — см. историю git.
  #
  # ПАЛИТРА:
  #   * Eldritch-Black — кастомная палитра для Noctalia:
  #     фоны #000000 (AMOLED), акценты из Eldritch (зелёный/фиолетовый/
  #     голубой/красный), основной текст — белый (#ffffff).
  # =====================================================================

  programs.niri.settings = {

    # Принудительно указываем qt6ct для всех Qt6-приложений.
    # Без этого переменная может оставаться "qt5ct" (см. `echo $QT_QPA_PLATFORMTHEME`),
    # и тема из qt6ct не применится к Dolphin и Kate.
    environment = {
      QT_QPA_PLATFORMTHEME = "qt6ct";
    };

    # Просим приложения (включая Firefox) не использовать свои
    # собственные декорации окна (CSD). Тогда Niri будет рисовать
    # единую рамку и скругление, и «двойного» эффекта не будет.
    prefer-no-csd = true;

    # Noctalia запускается при старте сессии.
    # Второй командой ставим обои через 1 секунду после старта Noctalia —
    # без задержки `noctalia msg` не успевает подключиться к IPC-сокету
    # (Noctalia поднимается ~1-2 сек), и команда молча падает.
    # Если после перелогина обои не появляются — увеличь sleep до 3-5.
    spawn-at-startup = [
      { command = [ "noctalia-shell" ]; }
  ];

    # Раскладка клавиатуры: та же, что в base/system/keyboard.nix.
    input.keyboard.xkb = {
      layout = "us,ru";
      options = "grp:caps_toggle,caps:escape";
    };

    # === Фон за рабочими пространствами (backdrop) ===
    # Устанавливаем чёрный цвет фона, который виден при переключении
    # рабочих столов и в обзоре (overview). Это убирает светлую
    # полоску и делает переходы более однородными.
    # Значение — любой цвет в формате #RRGGBB или #RRGGBBAA.
    overview = {
      backdrop-color = "#000000";
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
        active.color = "#37f499";
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

            # === Прозрачность для foot ===
      # app-id для foot — просто "foot".
      # opacity 0.85 означает 85% непрозрачности (15% прозрачности).
      {
        matches = [ { app-id = "foot"; } ];
        opacity = 1.00;
      }

      # === Прозрачность для Kate ===
      # app-id для Kate в KDE обычно "org.kde.kate".
      {
        matches = [ { app-id = "org.kde.kate"; } ];
        opacity = 1.00;
      }

      # === Прозрачность для Dolphin ===
      # app-id для Dolphin — "org.kde.dolphin".
      {
        matches = [ { app-id = "org.kde.dolphin"; } ];
        opacity = 1.00;
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
      # === Скриншоты (через Noctalia) ===
      # F6 (работает как Fn+F6) на этом железе отправляет KEY_S и НЕ
      # переназначается через keyd/evremap (известное ограничение
      # WMI-устройств ASUS, issue #1181). Поэтому скриншоты вынесены
      # на свободные комбинации Mod+Shift+Z/X/C.
      #
      # Команды Noctalia (v5+):
      #   screenshot-region     — выделение области + редактор
      #   screenshot-fullscreen — весь экран + редактор
      #
      # Если команда не срабатывает, проверьте точный синтаксис:
      #   noctalia msg --help | grep -i screenshot
      # ================================================================
      "Mod+Shift+Z".action.spawn-sh = "noctalia msg screenshot-region";
      "Mod+Shift+X".action.spawn-sh = "noctalia msg screenshot-fullscreen";
      "Mod+Shift+C".action.spawn-sh = "noctalia msg panel-toggle clipboard";

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
      "Mod+Escape".action.spawn = "loginctl lock-session";
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

      # AIMP блокирует Niri/Wayland. Маскируем окружение под KDE:
      #   -u WAYLAND_DISPLAY       — убирает WAYLAND_DISPLAY только для AIMP
      #   GDK_BACKEND=x11          — GTK-виджеты идут через XWayland
      #   XDG_CURRENT_DESKTOP=KDE  — прячет Niri от проверки AIMP
      #   XDG_SESSION_DESKTOP=KDE  — дополнительная маскировка
      #   XDG_SESSION_TYPE=x11     — AIMP думает, что сессия X11
      "Mod+P".action.spawn-sh = "env -u WAYLAND_DISPLAY GDK_BACKEND=x11 XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE XDG_SESSION_TYPE=x11 aimp";


      "Mod+M".action.spawn = "waydroid";        # Waydroid UI
      "Mod+Shift+M".action.spawn = "waydroid-stop";  # полное закрытие Waydroid

            # --- Запуск и остановка LLM-сервисов ---
      # Mod+<буква>       — запуск
      # Mod+Shift+<буква> — полное закрытие (аналог «Ctrl+C» для сервиса)
      #
      # ВАЖНО: все stop-команды уже определены в llm/*/commands.nix —
      # они вызывают podman stop с корректными таймаутами и очисткой.
      # Здесь только биндинги.

      # llama.cpp ROCm (порт 8085)
      "Mod+L".action.spawn = "llama-rocm-start";
      "Mod+Shift+L".action.spawn = "llama-rocm-stop";

      # Unsloth Studio (порт 8005)
      "Mod+U".action.spawn = "unsloth-start";
      "Mod+Shift+U".action.spawn = "unsloth-stop";

      # DeepSeek Harness (локальная сборка, порт 7718)
      # ВНИМАНИЕ: команда именно dsh-local-stop, а не dsh-stop —
      # у DSH две реализации (local и podman), и stop у каждой свой.
      "Mod+H".action.spawn = "dsh-local-start";
      "Mod+Shift+H".action.spawn = "dsh-local-stop";

      # Strata (порт 5747)
      "Mod+I".action.spawn = "strata-start";
      "Mod+Shift+I".action.spawn = "strata-stop";


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
  # Конфигурация вынесена в отдельный файл ui/niri/noctalia.toml
  # (экспортирован через `noctalia config export full`).
  #
  # ВАЖНО: путь ./noctalia.toml относительный — файл должен лежать
  # рядом с home.nix, в той же директории ui/niri/.
  # Файл ОБЯЗАТЕЛЬНО должен быть в git (git add), иначе flake его
  # не увидит при сборке, и nix flake check упадёт с «path does not exist».
  #
  # Плагин kenn/keybind-cheatsheet уже прописан в самом TOML
  # (секция [plugins] enabled = [ "kenn/keybind-cheatsheet" ]),
  # поэтому дублировать его в Nix не нужно.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;

    # Home Manager-модуль принимает путь к .toml файлу напрямую.
    # См. документацию: programs.noctalia.settings может быть
    # attrset, raw TOML string или path к .toml.
    settings = ./noctalia.toml;

    # =====================================================================
    # Кастомная палитра "Eldritch-Black".
    #
    # Сочетает лучшее из двух палитр:
    #   * фоны (mSurface, mSurfaceVariant, mShadow, terminal.background) —
    #     чисто чёрные #000000, как в Lilac AMOLED;
    #   * акценты (mPrimary/mSecondary/mTertiary/mError) — оригинальные
    #     цвета Eldritch: зелёный #37f499, фиолетовый #a48cf2,
    #     голубой #04d1f9, красный #f16c75;
    #   * основной текст — БЕЛЫЙ (#ffffff), чтобы не мешал цветным
    #     акцентам и хорошо читался на чёрном.
    #
    # Light-режим полностью дублирует dark — светлая тема не нужна,
    # но модуль требует её наличия.
    #
    # Чтобы палитра применилась, в noctalia.toml должно быть:
    #   [theme]
    #   source = "custom"
    #   custom_palette = "Eldritch-Black"
    #   pure_black_dark = false
    # =====================================================================
    customPalettes."Eldritch-Black" = let
      eldritchBlack = {
        # --- Акценты (Eldritch) ---
        mPrimary = "#37f499";        # зелёный
        mOnPrimary = "#000000";
        mSecondary = "#a48cf2";      # фиолетовый
        mOnSecondary = "#000000";
        mTertiary = "#04d1f9";       # голубой
        mOnTertiary = "#000000";
        mError = "#f16c75";          # красный
        mOnError = "#000000";

        # --- Фоны (чистый чёрный, AMOLED) ---
        mSurface = "#000000";
        mSurfaceVariant = "#000000";
        mShadow = "#000000";
        mOutline = "#4c3a70";        # границы — тёмно-фиолетовый Eldritch
        mHover = "#a48cf2";          # hover — фиолетовый (как mSecondary)
        mOnHover = "#000000";

        # --- Текст (БЕЛЫЙ) ---
        # mOnSurface — основной текст на фоне (заголовки, кнопки).
        # mOnSurfaceVariant — приглушённый текст (подписи, hint).
        # Оба белые, variant чуть серее для визуальной иерархии.
        mOnSurface = "#ffffff";
        mOnSurfaceVariant = "#d0d0d0";

        # --- Терминал ---
        terminal = {
          background = "#000000";
          foreground = "#ffffff";            # белый основной текст
          cursor = "#37f499";                # курсор — зелёный акцент
          cursorText = "#000000";
          selectionBg = "#4c3a70";           # выделение — тёмно-фиолетовый
          selectionFg = "#ffffff";
          normal = {
            black = "#000000";
            red = "#f16c75";
            green = "#37f499";
            yellow = "#f1fc79";
            blue = "#7081d0";
            magenta = "#a48cf2";
            cyan = "#04d1f9";
            white = "#ffffff";
          };
          bright = {
            black = "#323449";
            red = "#f16c75";
            green = "#37f499";
            yellow = "#f1fc79";
            blue = "#7081d0";
            magenta = "#a48cf2";
            cyan = "#04d1f9";
            white = "#ffffff";
          };
        };
      };
    in {
      # dark — рабочая палитра
      dark = eldritchBlack;
      # light — полный дубль dark (светлая тема не используется)
      light = eldritchBlack;
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
  #
  # Примечание: отдельно ставить pkgs.libsecret и pkgs.gnome-keyring
  # в home.packages не нужно — libsecret тянется через
  # git.override { withLibsecret = true; }, а gnome-keyring поднимается
  # системным сервисом services.gnome.gnome-keyring.enable = true
  # (см. ui/niri/niri.nix).
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
  # Базовая GTK-тема, на которую «ложится» CSS от Noctalia.
  #
  # Без этого блока Home Manager не создаёт settings.ini,
  # и GTK-приложения (включая портал) не знают, какую тему использовать.
  #
  # Цвета поверх этой темы даёт шаблон gtk3/gtk4 от Noctalia —
  # он генерирует ~/.config/gtk-3.0/gtk.css с @import "noctalia.css".
  #
  # font — JetBrainsMono Nerd Font (единственный кастомный шрифт
  # в системе после удаления Montserrat). ВАЖНО: JetBrains Mono —
  # моноширинный, в тексте интерфейса (кнопки, заголовки диалогов)
  # буквы будут одинаковой ширины. Если это покажется неудобным —
  # можно вернуть отдельный sans-serif (например, DejaVu Sans) или
  # поставить шрифт из nixpkgs: `pkgs.inter` или `pkgs.noto-fonts`.
  # =====================================================================
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 10;
    };
  };

  # =====================================================================
  # Qt/KDE: тема, шрифт и цвета — через qt6ct.
  #
  # qt6ct — мост между Noctalia (шаблон KColorScheme) и Qt-приложениями
  # (Dolphin, Kate). Выбор схемы "noctalia" в qt6ct GUI — единственный
  # не декларативный шаг; после него qt6ct.conf фиксируется через force
  # ниже, и n13rebuild его не затирает.
  #
  # QT_QPA_PLATFORMTHEME=qt6ct дополнительно выставлен в
  # programs.niri.settings.environment выше — на случай, если
  # qt-модуль не пробросит его в сессию Niri.
  #
  # Fonts: JetBrainsMono Nerd Font — для Qt-приложений используем
  # моноширинный (Kate, терминальные вкладки, панели Dolphin).
  # Строка формата: "Family,size,-1,weight,italic,underline,strikeout,
  # fixedPitch,styleHint,stretch,letterSpacing,...". Взято из вывода
  # `qt6ct` после ручной настройки — если размер/начертание не
  # подхватятся, откройте qt6ct → Fonts и проверьте значения.
  # =====================================================================
  qt = {
    enable = true;
    platformTheme.name = "qtct";

    qt6ctSettings = {
      Appearance = {
        custom_palette = true;
        color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/noctalia.conf";
        # При необходимости можно также задать стиль, иконки и т.д.
        # style = "Breeze";
        # icon_theme = "breeze-dark";
      };

      Fonts = {
        # general — основной шрифт UI (панели, меню).
        # fixed — моноширинный (редактор кода, терминал в Kate).
        # Оба ставим в JetBrainsMono Nerd Font, чтобы UI и контент
        # выглядели единообразно.
        general = "JetBrainsMono Nerd Font,11,-1,5,500,0,0,0,0,0,0,0,0,0,0,1";
        fixed = "JetBrainsMono Nerd Font,11,-1,5,500,0,0,0,0,0,0,0,0,0,0,1";
      };
    };
  };

  # =====================================================================
  # kdeglobals: явно указываем KDE-приложениям (Dolphin, Kate)
  # использовать цветовую схему "noctalia" из
  # ~/.local/share/color-schemes/noctalia.colors (её генерирует
  # шаблон KColorScheme в Noctalia).
  #
  # Без этого файла KDE-приложения могут откатываться к светлой Breeze.
  # force = true — чтобы перезаписать kdeglobals, если он был создан
  # вручную (например, после запуска System Settings).
  # =====================================================================
  xdg.configFile."kdeglobals".force = true;
  xdg.configFile."kdeglobals".text = ''
    [UiSettings]
    ColorScheme=noctalia
  '';

  # qt6ct пишет свой конфиг при нажатии Apply в GUI (~/.config/qt6ct/qt6ct.conf).
  # Home Manager теперь тоже управляет этим файлом (через qt.qt6ctSettings
  # выше), и без force падает с «would be clobbered».
  # force = true — перезапись существующего файла декларативным содержимым.
  xdg.configFile."qt6ct/qt6ct.conf".force = true;

  # =====================================================================
  # Переменные окружения для курсора мыши.
  #
  # QT_QPA_PLATFORMTHEME выставляется qt-модулем автоматически
  # (qt.platformTheme.name = "qtct") и дублируется в
  # programs.niri.settings.environment для надёжности.
  # QT_STYLE_OVERRIDE больше не используется (Kvantum удалён).
  # =====================================================================
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # =====================================================================
  # Обои: симлинк всей папки ui/wallpapers/ в ~/Pictures/Wallpapers.
  #
  # Файлы будут указывать в /nix/store (read-only) — это нормально,
  # Noctalia их только читает. При старте сессии
  # (см. spawn-at-startup выше) выставляется nebula.jpg как дефолт.
  #
  # Плюс такого подхода: добавил новый jpg в ui/wallpapers/ →
  # n13rebuild → он уже в ~/Pictures/Wallpapers/. Минус: добавить
  # обои «на лету», не пересобирая систему, нельзя.
  # =====================================================================
  home.file."Pictures/Wallpapers".source = ../wallpapers;

  # =====================================================================
  # fontconfig: шрифты по умолчанию для всей системы.
  #
  #   sansSerif = JetBrainsMono Nerd Font — интерфейсы, GTK-приложения,
  #                                          диалоги Firefox.
  #   monospace = JetBrainsMono Nerd Font — терминал (foot), btop,
  #                                          редакторы кода.
  #
  # ВАЖНО: JetBrains Mono — моноширинный, в UI текст будет
  # выровнен по сетке (как в терминале). Это осознанный выбор после
  # удаления Montserrat. Если покажется неудобным — добавь в
  # `sansSerif` пропорциональный шрифт, например:
  #   sansSerif = [ "Inter" "DejaVu Sans" ];   (после pkgs.inter)
  # fontconfig выберет первый доступный.
  #
  # JetBrainsMono Nerd Font (не просто JetBrains Mono) — потому что
  # в btop, foot и некоторых плагинах Noctalia используются иконки
  # Nerd Font (U+E000–U+F8FF). Без них будут «квадратики».
  # =====================================================================
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      sansSerif = [ "JetBrainsMono Nerd Font" ];
      monospace = [ "JetBrainsMono Nerd Font" ];
    };
  };

  # =====================================================================
  # foot (терминал).
  #
  # include — тема Noctalia (цвета; файл генерируется шаблоном "foot").
  # font — JetBrainsMono Nerd Font. В терминале пропорциональный шрифт
  # (Montserrat) непригоден — буквы пляшут, иконки не выравниваются.
  # JetBrains Mono — специально для кода/терминала, + Nerd Font-иконки
  # для btop, starship, tmux и т.п.
  # =====================================================================
  programs.foot = {
    enable = true;
    settings = {
      main = {
        include = "~/.config/foot/themes/noctalia";
        font = "JetBrainsMono Nerd Font:size=9";
      };
    };
  };

    programs.firefox = {
    enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox"; # Указываем путь к профилям
    profiles.default = {
      # ... другие настройки профиля ...

      # Подключаем userChrome.css для кастомизации интерфейса.
userChrome = ''
  /* ============================================================
     Firefox UI — Eldritch-Black (Полная версия)
     Черные фоны, белый текст, скругления
     ============================================================ */

  :root {
    --eldritch-green: #37f499;
    --eldritch-purple: #a48cf2;
    --eldritch-blue: #04d1f9;
    --eldritch-red: #f16c75;
    --eldritch-white: #ffffff;
    --eldritch-black: #000000;
    --eldritch-radius: 8px;
  }

  /* --- 1. Панель вкладок и адресная строка --- */
  #TabsToolbar,
  #tabbrowser-tabs,
  .tabbrowser-tab,
  #nav-bar,
  #urlbar-container,
  #searchbar {
    background-color: var(--eldritch-black) !important;
    color: var(--eldritch-white) !important;
  }

  .tabbrowser-tab[selected="true"] .tab-background {
    background-color: var(--eldritch-purple) !important;
    opacity: 0.8 !important;
    border-radius: var(--eldritch-radius) !important;
  }

  .tab-label,
  #urlbar-input,
  #urlbar,
  toolbarbutton {
    color: var(--eldritch-white) !important;
  }

  /* --- 2. Панель закладок (Bookmarks Toolbar) --- */
  /* Убираем серый фон, делаем его черным. */
  #PersonalToolbar {
    background-color: var(--eldritch-black) !important;
    color: var(--eldritch-white) !important;
  }

  /* --- 3. Контекстные меню и выпадающие списки (menupopup) --- */
  /* Задаем черный фон, скругление и убираем стандартную рамку. */
  menupopup {
    --menu-background-color: var(--eldritch-black) !important;
    --menu-border-radius: var(--eldritch-radius) !important;
    --menu-border-color: transparent !important; /* Убираем стандартную рамку */
    background-color: var(--menu-background-color) !important;
    border: 1px solid var(--eldritch-purple) !important; /* Добавляем свою тонкую рамку */
    border-radius: var(--menu-border-radius) !important;
    padding: 4px !important; /* Небольшой отступ внутри меню */
  }

  /* Убираем лишние отступы у пунктов меню, чтобы выглядело компактнее */
  menupopup > menuitem,
  menupopup > menu {
    padding-block: 4px !important;
    padding-inline-start: 8px !important;
  }

  /* --- 4. Всплывающие подсказки (tooltip) --- */
  /* Отключаем нативную отрисовку и задаем свои стили. */
  tooltip {
    -moz-appearance: none !important;
    background-color: var(--eldritch-black) !important;
    color: var(--eldritch-white) !important;
    border: 1px solid var(--eldritch-purple) !important;
    border-radius: var(--eldritch-radius) !important;
    padding: 4px 8px !important;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5) !important;
  }

  /* --- 5. Прочие элементы --- */
  #navigator-toolbox {
    border-bottom: 1px solid var(--eldritch-purple) !important;
  }
  #urlbar {
    border-radius: var(--eldritch-radius) !important;
  }
'';

 userContent = ''
    /* Применяем стили только к внутренним страницам Firefox */
    @-moz-document url(about:newtab), url(about:home) {
      /* Устанавливаем черный фон для главной страницы */
      :root {
        --newtab-background-color: #000000 !important;
      }
      /* Убедимся, что текст белый */
      :root {
        --newtab-text-primary-color: #ffffff !important;
      }
    }
  '';

      # Обязательно включаем загрузку userChrome.css
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        # ... другие настройки ...
      };
    };
  };

# systemd.user.services.polkit-gnome-authentication-agent-1 = {
#   Unit = {
#     Description = "polkit-gnome-authentication-agent-1";
#     After = [ "graphical-session.target" ];
#     Wants = [ "graphical-session.target" ];
#   };
#   Service = {
#     Type = "simple";
#     ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
#     Restart = "on-failure";
#     RestartSec = 1;
#     TimeoutStopSec = 10;
#   };
#   Install = {
#     WantedBy = [ "graphical-session.target" ];
#   };
# };

# systemd.user.services.kded6 = {
#   Unit = {
#     Description = "KDE Daemon (kded6) for SolidUiServer";
#     After = [ "graphical-session.target" ];
#     Wants = [ "graphical-session.target" ];
#   };
#   Service = {
#     Type = "simple";
#     ExecStart = "${pkgs.kdePackages.kded}/bin/kded6";
#     Restart = "on-failure";
#     RestartSec = 1;
#   };
#   Install = {
#     WantedBy = [ "graphical-session.target" ];
#   };
# };


  # === Пакеты ===
  home.packages = with pkgs; [
    foot                  # Wayland-терминал
    wofi                  # standalone-лаунчер
    kdePackages.dolphin   # файловый менеджер

    # --- Тёмная тема Qt/KDE ---
    kdePackages.qt6ct
    adwaita-icon-theme

    # предоставляет kded6 и SolidUiServer
#     kdePackages.kded

    polkit_gnome

    # --- Шрифты ---
    # JetBrains Mono из nixpkgs (актуальная версия + Nerd Font иконки).
    # Имя семейства в fontconfig — "JetBrainsMono Nerd Font".
    # Montserrat удалён — см. историю git.
    nerd-fonts.jetbrains-mono

    # --- Git: libsecret для сохранения паролей ---
    # libsecret и gnome-keyring не нужны отдельно:
    #   * libsecret тянется через git.override { withLibsecret = true; };
    #   * gnome-keyring поднимается сервисом
    #     services.gnome.gnome-keyring.enable = true (см. ui/niri/niri.nix).

    # --- Мультимедийные утилиты для F1-F12 ---
    # wireplumber даёт команду wpctl (громкость).
    # brightnessctl — управление подсветкой экрана.
    # playerctl — MPRIS-медиа-клавиши (play/pause/next/prev).
    wireplumber
    brightnessctl
    playerctl

    # --- Архиваторы ---
    # Ark — для Dolphin (двойной клик по .zip открывает Ark).
    # file-roller — GTK-альтернатива на случай, если понадобится.
    # unzip/zip — консольные утилиты (нужны скриптам и для случаев,
    # когда графический архиватор не справляется).
    kdePackages.ark
    file-roller
    unzip
    zip
    nethogs

  (writeShellScriptBin "sr" ''exec sudo reboot'')
  (writeShellScriptBin "c"  ''exec clear'')



(writeShellScriptBin "luksmount" ''
    set -u

    find_mapper() {
      local dev="$1"
      local base holder h name
      base=$(basename "$(readlink -f "$dev")")
      for holder in "/sys/class/block/$base/holders/"*; do
        [ -e "$holder" ] || continue
        h=$(basename "$(readlink -f "$holder")")
        if [ -r "/sys/class/block/$h/dm/name" ]; then
          name=$(cat "/sys/class/block/$h/dm/name")
          echo "/dev/mapper/$name"
          return 0
        fi
      done
      return 1
    }

    mapper_mount() {
      findmnt -n -o TARGET "$1" 2>/dev/null | head -n1
    }

    describe_dev() {
      local d="$1" size pk model mapper mp fstype label status
      size=$(lsblk -lpno SIZE "$d" | head -n1)
      pk=$(lsblk -lpno PKNAME "$d" | head -n1)
      model=""
      [ -n "$pk" ] && model=$(lsblk -dpno MODEL "/dev/$pk" 2>/dev/null | xargs || true)
      mapper=$(find_mapper "$d" || true)
      fstype=""; label=""
      if [ -n "$mapper" ] && [ -e "$mapper" ]; then
        mp=$(mapper_mount "$mapper")
        if [ -n "$mp" ]; then
          status="разблокирован, смонтирован в $mp"
        else
          status="разблокирован как $mapper (не смонтирован)"
        fi
        fstype=$(lsblk -dpno FSTYPE "$mapper" 2>/dev/null | xargs || true)
        label=$(lsblk -dpno LABEL "$mapper" 2>/dev/null | xargs || true)
      else
        status="не разблокирован"
      fi
      printf "     Размер:   %s\n" "$size"
      [ -n "$model" ] && printf "     Носитель: %s\n" "$model"
      [ -n "$fstype" ] && printf "     ФС:       %s\n" "$fstype"
      [ -n "$label" ] && printf "     Метка:    %s\n" "$label"
      printf "     Статус:   %s\n" "$status"
    }

    if [ "$#" -ge 1 ]; then
      dev="$1"
    else
      mapfile -t devices < <(lsblk -lpno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}')
      if [ "''${#devices[@]}" -eq 0 ]; then
        echo "LUKS-устройства не найдены." >&2
        exit 1
      fi
      echo "Доступные LUKS-устройства:"
      echo
      for i in "''${!devices[@]}"; do
        d="''${devices[$i]}"
        printf "  %d) %s\n" "$((i+1))" "$d"
        describe_dev "$d"
        echo
      done
      read -rp "Введите номер устройства (Enter — отмена): " choice
      [ -z "''${choice:-}" ] && exit 0
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "''${#devices[@]}" ]; then
        echo "Неверный выбор." >&2
        exit 1
      fi
      dev="''${devices[$((choice-1))]}"
    fi

    [ -e "$dev" ] || { echo "Устройство $dev не существует." >&2; exit 1; }

    mapper=$(find_mapper "$dev" || true)
    if [ -n "$mapper" ] && [ -e "$mapper" ]; then
      mp=$(mapper_mount "$mapper")
      if [ -n "$mp" ]; then
        echo "$dev уже разблокирован и смонтирован в $mp. Ничего делать не нужно."
        exit 0
      fi
      echo "$dev уже разблокирован как $mapper"
    else
      echo "Разблокировка $dev (введите пароль LUKS)..."
      udisksctl unlock --block-device "$dev" || { echo "Разблокировка не удалась." >&2; exit 1; }
      mapper=$(find_mapper "$dev" || true)
      [ -n "$mapper" ] && [ -e "$mapper" ] || { echo "Не удалось найти маппер после разблокировки." >&2; exit 1; }
    fi

    echo "Монтирование $mapper ..."
    udisksctl mount --block-device "$mapper"

    mp=$(mapper_mount "$mapper")
    echo
    echo "=== Информация о томе ==="
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS "$dev"
    if [ -n "$mp" ]; then
      echo
      df -h "$mp"
      echo
      echo "Точка монтирования: $mp"
    fi
  '')

    (writeShellScriptBin "luksunmount" ''
    set -u

    find_mapper() {
      local dev="$1"
      local base holder h name
      base=$(basename "$(readlink -f "$dev")")
      for holder in "/sys/class/block/$base/holders/"*; do
        [ -e "$holder" ] || continue
        h=$(basename "$(readlink -f "$holder")")
        if [ -r "/sys/class/block/$h/dm/name" ]; then
          name=$(cat "/sys/class/block/$h/dm/name")
          echo "/dev/mapper/$name"
          return 0
        fi
      done
      return 1
    }

    mapper_mount() {
      findmnt -n -o TARGET "$1" 2>/dev/null | head -n1
    }

    # true, если маппер смонтирован в системный путь (или куда-то неизвестное)
    is_system_mapper() {
      local mapper="$1" mp
      mp=$(mapper_mount "$mapper")
      [ -z "$mp" ] && return 1
      case "$mp" in
        /run/media/*|/media/*|/mnt/*) return 1 ;;  # безопасные точки
        *) return 0 ;;                              # всё остальное — системное
      esac
    }

    describe_dev() {
      local d="$1" size pk model mapper mp status
      size=$(lsblk -lpno SIZE "$d" | head -n1)
      pk=$(lsblk -lpno PKNAME "$d" | head -n1)
      model=""
      [ -n "$pk" ] && model=$(lsblk -dpno MODEL "/dev/$pk" 2>/dev/null | xargs || true)
      mapper=$(find_mapper "$d" || true)
      if [ -n "$mapper" ] && [ -e "$mapper" ]; then
        if is_system_mapper "$mapper"; then
          status="системный (закрытие запрещено)"
        else
          mp=$(mapper_mount "$mapper")
          if [ -n "$mp" ]; then
            status="разблокирован, смонтирован в $mp"
          else
            status="разблокирован как $mapper (не смонтирован)"
          fi
        fi
      else
        status="не разблокирован (нечего закрывать)"
      fi
      printf "     Размер:   %s\n" "$size"
      [ -n "$model" ] && printf "     Носитель: %s\n" "$model"
      printf "     Статус:   %s\n" "$status"
    }

    if [ "$#" -ge 1 ]; then
      dev="$1"
    else
      # Собираем только те LUKS-устройства, которые можно безопасно закрыть
      mapfile -t all_devices < <(lsblk -lpno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}')
      devices=()
      for d in "''${all_devices[@]}"; do
        mapper=$(find_mapper "$d" || true)
        if [ -n "$mapper" ] && [ -e "$mapper" ] && is_system_mapper "$mapper"; then
          continue
        fi
        devices+=("$d")
      done

      if [ "''${#devices[@]}" -eq 0 ]; then
        echo "Нет LUKS-устройств, доступных для безопасного закрытия."
        exit 0
      fi

      echo "LUKS-устройства (системные исключены):"
      echo
      for i in "''${!devices[@]}"; do
        d="''${devices[$i]}"
        printf "  %d) %s\n" "$((i+1))" "$d"
        describe_dev "$d"
        echo
      done
      read -rp "Введите номер устройства (Enter — отмена): " choice
      [ -z "''${choice:-}" ] && exit 0
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "''${#devices[@]}" ]; then
        echo "Неверный выбор." >&2
        exit 1
      fi
      dev="''${devices[$((choice-1))]}"
    fi

    [ -e "$dev" ] || { echo "Устройство $dev не существует." >&2; exit 1; }

    mapper=$(find_mapper "$dev" || true)
    if [ -z "$mapper" ] || [ ! -e "$mapper" ]; then
      echo "$dev не разблокирован — нечего закрывать."
      exit 0
    fi

    if is_system_mapper "$mapper"; then
      echo "Отказано: $mapper смонтирован в системный путь ($(mapper_mount "$mapper"))." >&2
      echo "Закрытие системного контейнера приведёт к краху системы." >&2
      exit 1
    fi

    mps=$(findmnt -n -R "$mapper" -o TARGET 2>/dev/null || true)
    if [ -n "$mps" ]; then
      echo "Размонтирование:"
      echo "$mps" | sed 's/^/  /'
      if ! udisksctl unmount -b "$mapper"; then
        echo "Не удалось размонтировать $mapper — возможно, том занят." >&2
        exit 1
      fi
      if findmnt -n -R "$mapper" -o TARGET >/dev/null 2>&1; then
        echo "Том всё ещё смонтирован, отмена." >&2
        exit 1
      fi
    fi

    echo "Закрытие LUKS-контейнера $dev ..."
    if ! udisksctl lock -b "$dev"; then
      echo "Закрытие не удалось." >&2
      exit 1
    fi
    [ -e "$mapper" ] && { echo "Внимание: $mapper всё ещё существует после lock." >&2; exit 1; }
    echo "Готово: $dev закрыт."
  '')

  ];
}
