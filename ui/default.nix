{ config, lib, ... }:

let
  cfg = config.kda.opts;
in
{
  # =====================================================================
  # ui/ — ось «оконная оболочка».
  #
  # Диспетчер подключает ровно один набор модулей в зависимости от
  # kda.opts.ui, заданного устройством:
  #   "kde"      -> ui/kde/     (Plasma 6, SDDM, plasma-specific сервисы)
  #   "hyprland" -> ui/hyprland/ (каркас под миграцию)
  #
  # ui/common/ подключается при ЛЮБОЙ графической оболочке — там лежит
  # всё, что не зависит от DE: Wayland-порталы, базовый libinput,
  # печать. Это снимает привязку base/ к KDE и готовит переход на
  # Hyprland: устройству достаточно поменять kda.opts.ui.
  # =====================================================================

  imports = [ ]
    # Общий слой: активен при любой graphical-shell-оси.
    ++ lib.optionals (cfg.ui != "none") [
      ./common/wayland.nix
      ./common/input.nix
      ./common/printing.nix
    ]
    # Собственно оболочки.
    ++ lib.optionals (cfg.ui == "kde") [ ./kde ]
    ++ lib.optionals (cfg.ui == "hyprland") [ ./hyprland ];
}
