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
    # Собственно оболочки. ВАЖНО: указываем ./kde/default.nix, а не ./kde —
    # Nix умеет импортировать директорию только через явный default.nix;
    # путь-директория в imports даёт «module ... does not look like a module».
    ++ lib.optionals (opts.ui == "kde") [ ./kde/default.nix ]
    ++ lib.optionals (opts.ui == "hyprland") [ ./hyprland/default.nix ];
}
