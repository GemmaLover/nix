{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/cliphist-hyprland.nix — история буфера обмена.
  #
  # Порт функциональности Klipper (буфер обмена Plasma): Klipper — часть
  # KDE-стека, на Hyprland его заменяет cliphist + демон wl-paste.
  # Сервис стартует вместе с graphical-сессией; хоткей вызова истории
  # (SUPER+V -> wtype вставка) задаётся в programs.hyprland.settings.bind
  # модуля power-lock-hyprland.nix (см. bind = [ "SUPER, V, exec, ..." ]).
  #
  # Хранение: cliphist store использует XDG_DATA_HOME (~/.local/share/cliphist).
  # =====================================================================
  systemd.user.services.cliphist-daemon = {
    Unit = {
      Description = "cliphist clipboard manager daemon (Klipper replacement)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
