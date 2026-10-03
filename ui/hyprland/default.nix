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
    # hypridle/hyprlock НЕ импортируются на уровне NixOS: модули
    # services.hypridle и programs.hyprlock.settings существуют только в
    # Home Manager (в nixpkgs у programs.hyprlock всего enable/package).
    # Конфиги локера/айдла живут в домашнем слое:
    # devices/z13/home-specific/power-lock-hyprland.nix.
  ];
}
