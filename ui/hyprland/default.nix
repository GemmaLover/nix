# =====================================================================
# ui/hyprland/ — ось «Hyprland» (каркас для миграции с KDE).
# Подключается при kda.opts.ui = "hyprland" (см. ui/default.nix).
# Карта миграции компонентов — в guide.md, раздел «Миграция на Hyprland».
#
# ФОРМАТ: attrset с imports, а не голый список (см. комментарий в
# ui/kde/default.nix). args пробрасываются явно — файл вызывается
# как функция из ui/default.nix.
# =====================================================================
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hyprland.nix
    # Портированные аналоги KDE-компонентов (карта — в guide.md):
    ./wlr-protocols.nix   # grim/slurp/cliphist/wtype/hyprpicker (Spectacle/Klipper/KColorChooser)
    ./hypridle.nix        # аналог связки PowerDevil+kscreenlocker (таймауты/гашение экрана)
    ./hyprlock.nix        # экран блокировки (аналог kscreenlocker Greeter)
  ];
}
