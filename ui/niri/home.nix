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
  #   * programs.noctalia.*     — сам шелл (панель, лаунчер, уведомления)
  #     и декларативное включение плагинов;
  #   * qt + xdg.configFile     — тёмная тема для Qt/KDE-приложений
  #     (Dolphin, Ark, Kate и т.д.), без ручного запуска kvantummanager;
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
    #   Mod+T         — терминал (foot)
    #   Mod+Q         — закрыть окно
    #   Mod+E         — файловый менеджер (Dolphin)
    #   Mod+D         — standalone-лаунчер (wofi)
    #   Mod+Space     — лаунчер Noctalia (v5+ IPC)
    #   Mod+Shift+Q   — меню питания Noctalia (v5+ IPC)
    #   Mod+F1        — шпаргалка Noctalia (плагин keybind-cheatsheet)
    #   Mod+Shift+L   — заблокировать сессию
    #   Mod+Shift+E   — выйти из Niri
    #
    # Перемещение окон:
    #   Mod+Shift+←/→           — сдвинуть колонку (порядок колонок)
    #   Mod+Shift+↑/↓           — переместить окно внутри колонки
    #   Mod+Ctrl+↓              — вынести окно в следующее рабочее
    #                             пространство (если его нет — Niri создаст
    #                             новое); фокус остаётся на текущем
    #   Mod+Ctrl+↑              — вынести окно в предыдущее рабочее
    #                             пространство
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
      # Шпаргалка по клавишам (плагин keybind-cheatsheet).
      # Официальный пример для Niri использует Mod+F1, а не Mod+/:
      # символ '/' в Niri парсится как `slash`, но на практике
      # биндинги с пунктуацией конфликтуют с раскладкой US/RU.
      # Источник: https://noctalia.dev/plugins/community/keybind-cheatsheet
      "Mod+F1" = {
        action.spawn-sh = "noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet";
      };

      # === Перемещение окон в текущем рабочем пространстве ===
      # Сдвинуть активную колонку влево/вправо (меняет порядок колонок).
      # Это и есть «перемещение выделенного окна в текущем десктопе»
      # для колонок (Niri — колоночный WM).
      "Mod+Shift+Left".action.move-column-left = { };
      "Mod+Shift+Right".action.move-column-right = { };

      # Переместить активное окно вверх/вниз внутри колонки.
      "Mod+Shift+Up".action.move-window-up = { };
      "Mod+Shift+Down".action.move-window-down = { };

      # === Вынос окна в новое / соседнее рабочее пространство ===
      # move-window-to-workspace-down/up перемещает именно ОКНО (не колонку).
      # Если следующего рабочего пространства нет — Niri создаёт новое.
      # focus = false — фокус остаётся на текущем рабочем пространстве:
      # вы «выносите» окно и продолжаете работу здесь.
      # Уберите focus = false, если хотите, чтобы фокус следовал за окном.
      "Mod+Ctrl+Down".action.move-window-to-workspace-down = { focus = false; };
      "Mod+Ctrl+Up".action.move-window-to-workspace-up = { focus = false; };

      # --- Скриншоты (встроенные в Niri, аналог Spectacle) ---
      "Print".action.screenshot = { };
      "Mod+Print".action.screenshot-window = { };
      "Mod+Shift+Print".action.screenshot-screen = { };
    };
  };

  # === Noctalia — Wayland-шелл ===
  # Включает systemd user service и регистрирует автозапуск.
  # Программный запуск уже прописан в spawn-at-startup выше.
  #
  # ВАЖНО: systemd.enable = true привязывает сервис к
  # graphical-session.target, который активен и в Plasma, и в Niri.
  # Пока ui = "niri" — это нормально. Если временно вернётесь на KDE,
  # поставьте systemd.enable = false, чтобы Noctalia не запускался
  # поверх Plasma.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;

    # === Декларативное включение плагинов Noctalia v5+ ===
    # `programs.noctalia.settings` конвертируется Home Manager-модулем
    # в TOML-конфиг (~/.config/noctalia/config.toml). Секция [plugins]
    # — это «user intent» (declarative-friendly): если плагин указан
    # в enabled, но ещё не установлен, Noctalia автоматически
    # подтянет его из community-источника (он включён по умолчанию)
    # при старте. Ручной клик в GUI не нужен.
    #
    # ID плагина: kenn/keybind-cheatsheet (author/plugin), панель:
    # cheatsheet. Именно этот ID используется в биндинге Mod+F1 выше.
    settings = {
      plugins = {
        enabled = [ "kenn/keybind-cheatsheet" ];
      };
    };
  };

  # =====================================================================
  # Тёмная тема для Qt/KDE-приложений (полностью декларативно).
  #
  # KDE-приложения (Dolphin, Ark, Kate, ...) под Niri не знают о
  # тёмной теме Plasma, поэтому по умолчанию рисуются в светлой.
  # Лечим на трёх уровнях:
  #
  #   1. qt.enable + platformTheme.name = "qtct": Qt-приложения читают
  #      платформенную тему из qt5ct/qt6ct. Это рекомендуемое значение
  #      в Home Manager (см. документацию qt.platformTheme.name).
  #
  #   2. qt.style.name = "kvantum": стиль Qt-приложений — Kvantum.
  #      qt.kvantum.enable = true + qt.kvantum.settings.General.theme
  #      декларативно записывают ~/.config/Kvantum/kvantum.kvconfig
  #      с выбранной темой (Kvantum-dark). Ручной запуск
  #      `kvantummanager` НЕ нужен.
  #
  #   3. xdg.configFile."kdeglobals": цветовая схема KDE-приложений
  #      (BreezeDark). KDE-приложения читают kdeglobals, чтобы взять
  #      палитру окон/текста/выделения. Без этого Dolphin остался бы
  #      светлым даже с Kvantum.
  #
  # ВАЖНО: qt.style и qt.platformTheme — это НЕ строки, а вложенные
  # атрибуты с полем name (submodule). Именно из-за строкового
  # присваивания nix flake check падал с «trying to define a value
  # of type string rather than an attribute set».
  #
  # ВАЖНО: home.sessionVariables.QT_QPA_PLATFORMTHEME и
  # QT_STYLE_OVERRIDE НЕ задаём — модуль qt выставляет их сам
  # (QT_QPA_PLATFORMTHEME=qt5ct, QT_STYLE_OVERRIDE=kvantum). Ручное
  # дублирование вызывало конфликт «has conflicting definition values».
  # =====================================================================
  qt = {
    enable = true;

    # "qtct" — правильное имя опции (использует qt5ct и qt6ct).
    # В документации Home Manager допустимые значения: gtk, gtk3,
    # gnome, adwaita, lxqt, qtct, kde, kde6.
    platformTheme.name = "qtct";

    # Стиль Qt-приложений — Kvantum.
    style.name = "kvantum";

    # Декларативная настройка Kvantum: Home Manager сам создаст
    # ~/.config/Kvantum/kvantum.kvconfig с указанной темой.
    # Это заменяет ручной запуск `kvantummanager` и отдельный
    # xdg.configFile для kvantum.kvconfig.
    kvantum = {
      enable = true;
      settings = {
        General = {
          theme = "Kvantum-dark";
        };
      };
    };
  };

  # kdeglobals: KDE-приложения (Dolphin, Ark, Kate, ...) читают цветовую
  # схему отсюда. BreezeDark — официальная тёмная схема KDE; файл схемы
  # приходит из пакета kdePackages.breeze (добавлен в home.packages ниже).
  #
  # ВАЖНО: с KDE Frameworks 6.19+ KDE-приложения ИГНОРИРУЮТ
  # `[General] ColorScheme`, если platformTheme не "kde". Именно это
  # было причиной светлых Dolphin и Kate при qt.platformTheme = qtct.
  # Ключ `[UiSettings] ColorScheme=qt6ct` явно указывает KDE-приложениям
  # использовать схему, связанную с qt6ct, и восстанавливает
  # ожидаемое поведение. Значение "qt6ct" соответствует нашему
  # qt.platformTheme.name = "qtct".
  xdg.configFile."kdeglobals".text = ''
    [General]
    ColorScheme=BreezeDark
    Name=Breeze Dark
    shadeSortColumn=true

    [KDE]
    widgetStyle=Breeze
    contrast=4

    # === НОВОЕ: ключ для KDE Frameworks 6.19+ ===
    # Без этой секции Dolphin, Kate и другие KDE-приложения
    # игнорируют цвета из kdeglobals, когда platformTheme не "kde".
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

  # Переменные окружения — только то, что модуль qt НЕ выставляет.
  # QT_QPA_PLATFORMTHEME и QT_STYLE_OVERRIDE задаются qt-модулем
  # автоматически (qt5ct / kvantum). Ручное дублирование вызывало
  # конфликт «has conflicting definition values» при nix flake check.
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # === Пакеты, которые нужны для базового workflow ===
  home.packages = with pkgs; [
    # --- Базовый workflow ---
    foot                  # Wayland-терминал (аналог Konsole)
    wofi                  # standalone-лаунчер (аналог Kickoff)
    kdePackages.dolphin   # файловый менеджер (Qt6/Wayland, привычный UI)

    # --- Тёмная тема Qt/KDE ---
    kdePackages.qt6ct                        # qt6ct: платформенная тема Qt6
    qt6Packages.qtstyleplugin-kvantum        # движок стилей Kvantum (тема Kvantum-dark)
    kdePackages.qtstyleplugin-kvantum        # Kvantum для KDE-приложений (Qt6)
    kdePackages.breeze                       # Breeze Dark: цветовые схемы + стиль Breeze
    kdePackages.breeze-icons                 # тёмные иконки для Dolphin и др.
    kdePackages.plasma-integration           # интеграция Qt с KDE: kdeglobals, палитры
    adwaita-icon-theme                       # тёмный курсор Adwaita (XCURSOR_THEME)
  ];
}
