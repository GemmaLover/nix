{ config, pkgs, ... }:

{
  # === Home Manager: пользователь lexi ===

  imports = [
    ./home-services.nix
    ./home-caffeine.nix
    ../../llm/home.nix
    ./plasma-power.nix
    ../../base/tools/portmaster-ui.nix
  ];

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
  # =====================================================================
  home.activation.fix-plasma-launchers = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    APPSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [ -f "$APPSRC" ]; then
      sed -i 's|file:///nix/store/[^/]*/share/applications/|applications:|g' \
        "$APPSRC" || true
    fi
  '';
}
