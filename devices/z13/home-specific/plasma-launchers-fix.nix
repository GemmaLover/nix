{ config, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/plasma-launchers-fix.nix — activation-хук
  # починки ярлыков KDE. Вынесён из home.nix при дезинтеграции KDE:
  # подключается диспетчером home-specific/default.nix только при
  # kda.opts.ui = "kde" (на Hyprland plasma-org.kde.*-конфигов нет).
  #
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
