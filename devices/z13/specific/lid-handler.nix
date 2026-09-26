{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # Скрипт, который выполняется при закрытии крышки.
  #
  # Udev не зависит от ингибиторов logind и PowerDevil — событие
  # приходит напрямую от ядра. Это обходит проблему, когда
  # PowerDevil блокирует обработку крышки в logind.
  #
  # Логика:
  #   - От сети: заблокировать сессию (kscreenlocker) + выключить
  #     подсветку клавиатуры. PowerDevil с настройкой
  #     idleTimeoutWhenLocked=immediately погасит дисплей.
  #   - От батареи: уйти в гибернацию.
  # =====================================================================
  lidHandler = pkgs.writeShellScript "lid-handler" ''
    set -euo pipefail

    # Определяем источник питания.
    # AC_ONLINE=1 — питание от сети, иначе — от батареи.
    AC_ONLINE=0
    for f in /sys/class/power_supply/AC*/online; do
      if [ -f "$f" ] && [ "$(cat "$f")" = "1" ]; then
        AC_ONLINE=1
        break
      fi
    done

    if [ "$AC_ONLINE" = "1" ]; then
      # --- От сети: блокировка экрана. ---
      ${pkgs.systemd}/bin/loginctl lock-sessions || true
    else
      # --- От батареи: гибернация. ---
      ${pkgs.systemd}/bin/systemctl hibernate || true
    fi
  '';
in
{
  # =====================================================================
  # Udev-правило: при закрытии крышки запускаем lidHandler.
  #
  # Событие крышки: SUBSYSTEM=="input", ATTRS{name}=="Lid Switch".
  # SWITCH_STATE=1 — крышка закрыта, 0 — открыта.
  # Реагируем только на закрытие.
  # =====================================================================
  services.udev.extraRules = ''
    ACTION=="switch", SUBSYSTEM=="input", ATTRS{name}=="Lid Switch", \
      ENV{SWITCH_STATE}=="1", \
      TAG+="systemd", \
      ENV{SYSTEMD_WANTS}="lid-handler.service"
  '';

  # =====================================================================
  # Systemd-сервис, который запускает lidHandler.
  # Type=oneshot — выполнить один раз и завершиться.
  # =====================================================================
  systemd.services.lid-handler = {
    description = "Handle lid close (lock on AC, hibernate on battery)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lidHandler;
    };
  };
}
