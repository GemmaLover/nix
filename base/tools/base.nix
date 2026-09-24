{ config, lib, pkgs, ... }:

{
  # Разрешаем несвободные пакеты (например, firmware для Wi-Fi)
  nixpkgs.config.allowUnfree = true;

  # === Базовые системные утилиты ===
  environment.systemPackages = with pkgs; [
    # --- Ядро и системные утилиты ---
    coreutils      # grep, cut, tr, mktemp и т.д.
    util-linux     # setpriv и другие утилиты
    shadow         # newuidmap, newgidmap
    gnutar         # tar-архивы
    gzip           # gzip-сжатие

    # --- Редакторы и файловые менеджеры ---
    vim            # Текстовый редактор
    tree           # Просмотр дерева каталогов
    file           # Определение типа файла
    which          # Поиск исполняемых файлов

    # --- Сеть ---
    wget           # Скачивание файлов
    curl           # HTTP-клиент
    unzip          # Распаковка ZIP

    # --- Git ---
    git            # Система контроля версий

    # --- Мониторинг ---
    htop           # Интерактивный монитор процессов
    btop           # Современный монитор ресурсов

    # --- Приложения ---
    firefox        # Веб-браузер
    libreoffice    # Офисный пакет
    vlc            # Медиаплеер
    keepassxc      # Менеджер паролей
    qbittorrent    # Торрент-клиент
    obs-studio     # Запись экрана и стриминг
    kdePackages.kleopatra  # Управление PGP-ключами
    krita          # Графический редактор
    librewolf      # Приватный браузер на базе Firefox
    brave          # Браузер с блокировкой рекламы
    putty          # SSH/Telnet клиент
    zenmap         # GUI для nmap
    parabolic      # Скачивание видео (ранее известен как Nickvision)


    # --- Утилиты ---
    tree           # Дерево каталогов
    file           # Определение типа файла

    # Демон простоя Wayland — используется для отключения подсветки
    # клавиатуры через 15 секунд бездействия.
    swayidle
  ];

  # === Git ===
  # Настройки Git на уровне системы
  programs.git = {
    enable = true;
    config = {
      # Здесь можно добавить глобальные настройки Git
      # Например, user.name и user.email
    };
  };
}
