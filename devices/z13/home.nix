{ config, lib, pkgs, kdaOpts ? { ui = "none"; profiles = [ ]; }, ... }:

{
  # === Home Manager: пользователь lexi ===
  #
  # Рефакторинг: DE-специфичные и железо-специфичные домашние модули
  # вынесены в ./home-specific/ (диспетчер — home-specific/default.nix,
  # подключает их по оси kda.opts.ui). Общие сервисы подсветки — в
  # ./home-services.nix. Профиль llm подключается по оси profiles.

  # ВАЖНО: NixOS/Home Manager импортируют директорию ТОЛЬКО если в ней
  # есть default.nix; без него путь-директория даёт «does not look like a
  # module». Здесь указываем явный ./home-specific/default.nix.
  imports = [ ]
    ++ [
      ./home-services.nix
      ./home-specific/default.nix
    ]
    ++ lib.optionals (lib.elem "llm" kdaOpts.profiles) [
      ../../llm/home.nix
    ];
    # Portmaster control: HM-модуль (home.packages + xdg.desktopEntries),
    # в baseline был закомментирован вместе с отключённым сервисом
    # portmaster — оставляем выключенным, но импортируемым при возврате.
    # ++ lib.optionals true [ ../../base/tools/portmaster-control.nix ];

  # Домашняя директория пользователя.
  home.homeDirectory = "/home/lexi";

  # Имя пользователя (должно совпадать с users.users.lexi).
  home.username = "lexi";

  # stateVersion для Home Manager — НЕ МЕНЯТЬ после первого применения.
  home.stateVersion = "26.05";

  # === Пакеты, установленные только для пользователя ===
  home.packages = with pkgs; [
    # Пользовательские приложения, которые не нужны системе.
  ];

  # === Git ===
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "lexi";
        email = "lexi@example.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # =====================================================================
  # Автоматическое исправление ярлыков KDE на панели задач.
  # (KDE-специфично: подключается только при kda.opts.ui = "kde",
  # см. home-specific/plasma-launchers-fix.nix.)
  #
  # KDE сохраняет ярлыки как абсолютные пути к .desktop-файлам
  # в /nix/store. После обновления системы или nix-collect-garbage
  # эти пути становятся недействительными, и иконки превращаются
  # в белые листы.
  #
  # Заменяем абсолютные пути на универсальные ссылки
  # "applications:имя.desktop", которые KDE резолвит динамически.
  #
  # Запускается при каждой пересборке (nixos-rebuild switch)
  # после записи конфигов, но до старта Plasma.
  # Сам activation-хук вынесен в home-specific/plasma-launchers-fix.nix
  # (подключается диспетчером только при ui = "kde") — здесь оставлено
  # описание для документации; на Hyprland ярлыки plasma не используются.
  # =====================================================================
}
