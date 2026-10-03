{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/caffeine-kde.nix — caffeine-ng (home-слой).
  #
  # Перенесено из удалённого devices/z13/home-caffeine.nix. Функционал
  # не зависит от железа z13, но привязан к KDE-трею, поэтому:
  #   * системная зависимость (пакет) — в ui/kde/caffeine.nix;
  #   * запуск трей-приложения (user-сервис) — здесь, подключается
  #     диспетчером home-specific/default.nix только при opts.ui = "kde".
  #
  # === Caffeine-ng ===
  # Автоматически блокирует засыпание и блокировку экрана,
  # когда приложение (Firefox, VLC и т.д.) запрашивает ингибирование.
  # Работает через D-Bus и MPRIS, поддерживает Wayland.
  #
  # ВАЖНО: в Home Manager НЕТ модуля programs.caffeine-ng (в отличие от
  # NixOS-опции services.caffeine, которая тоже не используется). caffeine-ng
  # — обычное трей-приложение: достаточно положить бинарь в PATH пользователя
  # и добавить автозапуск (XDG autostart работает и на Plasma, и на Hyprland
  # через xdg-desktop-portal). Запускается вручную из трея по необходимости.
  # =====================================================================
  home.packages = [ pkgs.caffeine-ng ];

  xdg.autostart.entries = [ "${pkgs.caffeine-ng}/share/applications/caffeine.desktop" ];
}
