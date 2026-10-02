# =====================================================================
# ui/kde/ — ось «KDE Plasma 6». Подключается при kda.opts.ui = "kde".
#
# Содержит ТОЛЬКО то, что зависит от Plasma:
#   plasma.nix   — сам DE, SDDM, Qt-пакеты.
#   caffeine.nix — caffeine-ng (ингибирование сна; на Hyprland его
#                  заменит hypridle/inhibit, поэтому он в KDE-оси).
#
# Сюда НЕ переносим: libinput-дефолты (-> ui/common/input.nix),
# CUPS (-> ui/common/printing.nix), ASUS-квирки (-> devices/z13/specific/),
# powerdevil/touchpad-конфиги пользователя (-> devices/z13/home-specific/).
# При миграции на Hyprland эта папка просто выключается сменой opts.ui.
#
# ФОРМАТ: модуль обязан быть attrset'ом, а не списком путей — NixOS
# принимает списки только внутри поля `imports` (см. lib/modules.nix:
# «module ... does not look like a module»). Ошибка была найдена при
# сборке на z13 (nixos-rebuild switch --flake .#z13).
# =====================================================================
{
  imports = [
    ./plasma.nix
    ./caffeine.nix
  ];
}
