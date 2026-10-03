# =====================================================================
# ui/ — ось «оконная оболочка».
#
# Диспетчер подключает ровно один набор модулей в зависимости от
# opts.ui, переданного хостом через mkSystem (аргумент `kda`, см.
# lib/mkSystem.nix):
#   "kde"      -> ui/kde/     (Plasma 6, SDDM, plasma-specific сервисы)
#   "hyprland" -> ui/hyprland/ (каркас под миграцию)
#
# ui/common/ подключается при ЛЮБОЙ графической оболочке — там лежит
# всё, что не зависит от DE: Wayland-порталы, базовый libinput,
# печать. Это снимает привязку base/ к KDE и готовит переход на
# Hyprland: устройству достаточно поменять kda.opts.ui.
#
# ВАЖНО: опции читаются из аргумента `kda`, а НЕ из `config.kda.opts`.
# Поле `imports` вычисляется ДО сборки config; ссылка на config здесь
# вызвала бы infinite recursion (проверено на z13). Значения opts.*
# задаются хостом в devices/<host>/config.nix и пробрасываются сюда
# фабрикой mkSystem как обычный attrset.
# =====================================================================
{ kda ? { ui = "none"; profiles = [ ]; }, lib, ... }:

let
  opts = kda;
in
{

  imports = [ ]
    # Общий слой: активен при любой graphical-shell-оси.
    ++ lib.optionals (opts.ui != "none") [
      ./common/wayland.nix
      ./common/input.nix
      ./common/printing.nix
    ]
    # Собственно оболочки. ВАЖНО: в imports кладётся ПУТЬ к default.nix,
    # а не результат его вызова. NixOS-модуль обязан быть одной из форм:
    # путь / attrset / функция args→attrset. Если вызвать default.nix
    # здесь вручную ({ config = {}; ... } или даже полными args), его
    # результат — обычный attrset без _module-метаданных — nixpkgs
    # принимает, но при любой ошибке внутри теряется контекст файла, а
    # раньше передавались неполные args и eval падал с «does not look
    # like a module». Правильный путь: импортировать файл как модуль —
    # nixpkgs сам подставит ему { config, lib, pkgs, ... } плюс
    # specialArgs (в них `kda` из mkSystem).
    ++ lib.optionals (opts.ui == "kde") [ ./kde/default.nix ]
    ++ lib.optionals (opts.ui == "hyprland") [ ./hyprland/default.nix ];
}
