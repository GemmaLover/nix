{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/asus-backlight-hyprland.nix — подсветка ASUS,
  # привязанная к hyprlock (IPC-сокет), порт asus-backlight-kde.nix.
  #
  # Выделено из plasma-power.nix при рефакторинге: сервис слушает
  # сигнал блокировки ЭКРАНА именно у kscreenlocker (KDE). При переходе
  # на Hyprland его заменит аналог на hyprlock IPC (socket2.sock),
  # а вызов asusctl останется тем же — поэтому файл лежит в слое
  # устройства, а не в ui/kde/.
  # ^ Это он и есть: ниже — hyprlock-версия того же сервиса.
  #
  # Отключать подсветку клавиатуры, когда экран заблокирован.
  # KDE при блокировке не трогает подсветку клавиатуры — это
  # отдельная подсистема (asusctl). Сервис слушает D-Bus-сигнал
  # org.kde.screensaver.ActiveChanged и вызывает asusctl.
  # ^ На Hyprland аналога D-Bus-сигнала нет: hyprlock пишет события
  #   "locked"/"unlocked" в сокет $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock2.
  #   Слушаем сокет и вызываем тот же asusctl.
  # =====================================================================
  systemd.user.services.kbd-backlight-lock-sync = {
    Unit = {
      Description = "Turn keyboard backlight off when screen is locked (hyprlock IPC)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "kbd-backlight-lock-sync-hypr" ''
        set -euo pipefail
        # Ждём появления сокета hyprlock (он создаётся при первом запуске
        # локера; HYPRLAND_INSTANCE_SIGNATURE приходит из окружения сессии).
        while [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; do sleep 2; done
        SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock2"
        while [ ! -e "$SOCK" ]; do sleep 2; done

        # socat подключается к unix-сокету и читает строки событий:
        # каждое событие — "locked" или "unlocked".
        # Порядок case'ов важен: "unlocked" содержит подстроку "locked",
        # поэтому проверка на разблокировку идёт первой.
        ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCK" \
        | while read -r line; do
            case "$line" in
              unlocked)
                # Разблокировано — низкая яркость.
                ${pkgs.asusctl}/bin/asusctl -k low 2>/dev/null || true
                ;;
              locked)
                # Заблокировано — гасим подсветку.
                ${pkgs.asusctl}/bin/asusctl -k off 2>/dev/null || true
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
