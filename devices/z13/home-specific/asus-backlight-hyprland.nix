{ config, pkgs, ... }:

let
  # =====================================================================
  # devices/z13/home-specific/asus-backlight-hyprland.nix — подсветка ASUS,
  # привязанная к блокировке экрана Hyprland (hyprlock IPC).
  #
  # Порт функциональности asus-backlight-kde.nix: там сервис слушал
  # D-Bus-сигнал org.kde.screensaver ActiveChanged. У Hyprland D-Bus-локера
  # нет — вместо него hyprlock поднимает Unix-сокет
  # $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock2,
  # по которому шлёт события "locked" / "unlocked". Вызов asusctl тот же —
  # поэтому файл лежит в слое устройства (железо), а не в ui/hyprland.
  #
  # Отключать подсветку клавиатуры, когда экран заблокирован.
  # Hyprland при блокировке не трогает подсветку клавиатуры — это
  # отдельная подсистема (asusctl). Сервис слушает сокет hyprlock и вызывает asusctl.
  # =====================================================================
in
{
  systemd.user.services.kbd-backlight-lock-sync = {
    Unit = {
      Description = "Turn keyboard backlight off when screen is locked (hyprlock IPC)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "kbd-backlight-lock-sync-hyprland" ''
        set -euo pipefail
        # hyprlock пишет события "locked"/"unlocked" в сокет .socket2 композитора.
        # Ждём появления сокета (сессия Hyprland могла ещё не подняться).
        while true; do
          SOCK="''${XDG_RUNTIME_DIR}/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock2"
          if [ -S "$SOCK" ]; then break; fi
          sleep 2
        done
        # nc --unix-conn читает поток событий; каждое "locked" гасит подсветку,
        # каждое "unlocked" возвращает низкую яркость.
        ${pkgs.netcat-openbsd}/bin/nc -U "$SOCK" \
        | while read -r event; do
            case "$event" in
              *locked*)
                # Заблокировано — гасим подсветку.
                ${pkgs.asusctl}/bin/asusctl -k off 2>/dev/null || true
                ;;
              *unlocked*)
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
