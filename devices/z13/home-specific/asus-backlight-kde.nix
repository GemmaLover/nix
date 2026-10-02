{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/asus-backlight-kde.nix — подсветка ASUS,
  # привязанная к KDE (D-Bus-сигнал org.kde.screensaver).
  #
  # Выделено из plasma-power.nix при рефакторинге: сервис слушает
  # сигнал блокировки ЭКРАНА именно у kscreenlocker (KDE). При переходе
  # на Hyprland его заменит аналог на hyprlock IPC (socket2.sock),
  # а вызов asusctl останется тем же — поэтому файл лежит в слое
  # устройства, а не в ui/kde/.
  #
  # Отключать подсветку клавиатуры, когда экран заблокирован.
  # KDE при блокировке не трогает подсветку клавиатуры — это
  # отдельная подсистема (asusctl). Сервис слушает D-Bus-сигнал
  # org.kde.screensaver.ActiveChanged и вызывает asusctl.
  # =====================================================================
  systemd.user.services.kbd-backlight-lock-sync = {
    Unit = {
      Description = "Turn keyboard backlight off when screen is locked";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "kbd-backlight-lock-sync" ''
        set -euo pipefail
        # dbus-monitor читает сигналы kscreenlocker.
        # Каждый ActiveChanged приходит строкой "boolean true" (locked)
        # или "boolean false" (unlocked).
        ${pkgs.dbus}/bin/dbus-monitor --session \
          "type='signal',interface='org.kde.screensaver',member='ActiveChanged'" \
        | while read -r line; do
            case "$line" in
              *"boolean true"*)
                # Заблокировано — гасим подсветку.
                ${pkgs.asusctl}/bin/asusctl -k off 2>/dev/null || true
                ;;
              *"boolean false"*)
                # Разблокировано — низкая яркость.
                ${pkgs.asusctl}/bin/asusctl -k low 2>/dev/null || true
                ;;
            esac
          done
      '';
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
