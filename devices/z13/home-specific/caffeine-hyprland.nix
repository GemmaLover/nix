{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/caffeine-hyprland.nix — caffeine-ng на Hyprland.
  #
  # Порт функциональности caffeine-kde.nix: тот же бинарь и тот же XDG
  # autostart. Отличие от KDE-версии только в механизме ингибирования:
  #   * в Plasma caffeine-ng дергал Solid/PowerDevil по D-Bus;
  #   * на Hyprland он использует xdg-desktop-portal (Inhibit), который
  #     работает через xdg-desktop-portal-hyprland (установлен в ui/hyprland).
  # Поэтому systemd-юниты/квирки не нужны — достаточно пакета и autostart.
  #
  # Запускать из трея waybar (модуль tray показывает caffeine-ng).
  # =====================================================================
  home.packages = [ pkgs.caffeine-ng ];

  xdg.autostart.entries = [ "${pkgs.caffeine-ng}/share/applications/caffeine.desktop" ];
}
