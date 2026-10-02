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
# =====================================================================
[
  ./plasma.nix
  ./caffeine.nix
]
