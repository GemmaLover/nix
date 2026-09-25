{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ПРОФИЛИ ПРОИЗВОДИТЕЛЬНОСТИ ASUS ROG FLOW Z13 (GZ302EA)
  #
  # Переключение идёт через штатный виджет KDE (батарейка в трее),
  # который управляет power-profiles-daemon (PPD). Наш сервис
  # z13-ppd-sync слушает изменения ActiveProfile в PPD и применяет
  # соответствующие настройки TDP и кривых вентиляторов через z13ctl.
  #
  # Меняйте значения в блоках balanced / eco / performance —
  # они применятся при следующем nixos-rebuild.
  #
  # Ограничения железа GZ302EA:
  #   - PL1 (sustained TDP): максимум 93W с флагом --force.
  #     Без --force ядро ограничивает PL1 до 75W.
  #   - Fan curve: ровно 8 точек "temp:pct%", температуры по возрастанию,
  #     скорости не убывают. Или fancurve --reset для заводской кривой.
  # =====================================================================

  # z13ctl-plus — локальный пакет из pkgs/.
  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "POWER SAVE" — соответствует power-saver в PPD
  # ---------------------------------------------------------------------
  eco = {
    tdp = 10;
    force = false;
    # Очень тихая кривая: вентиляторы стоят до 60°C, 100% только к 90°C.
    fan-curve = "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "BALANCED" — соответствует balanced в PPD
  # ---------------------------------------------------------------------
  balanced = {
    tdp = 75;
    force = false;
    # Заводская кривая ASUS.
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "PERFORMANCE" — соответствует performance в PPD
  # ---------------------------------------------------------------------
  performance = {
    tdp = 93;
    force = true;
    # Агрессивная кривая: 100% на 75°C.
    fan-curve = "45:0%,50:15%,55:30%,60:50%,65:70%,70:85%,75:100%,80:100%";
  };

  # ---------------------------------------------------------------------
  # mkApplyProfile — shell-скрипт применения одного профиля.
  # Через writeShellApplication, чтобы z13ctl был в PATH.
  # ---------------------------------------------------------------------
  mkApplyProfile = physicalName: p: pkgs.writeShellApplication {
    name = "z13-apply-${physicalName}";
    runtimeInputs = [ z13ctl-plus ];
    text = ''
      set -euo pipefail
      echo "[z13-profile] Применяю профиль '${physicalName}'..."

      # 1. Физический профиль (quiet | balanced | performance).
      z13ctl profile --set ${physicalName}

      # 2. TDP.
      ${if p.force
        then "z13ctl tdp --set ${toString p.tdp} --force"
        else "z13ctl tdp --set ${toString p.tdp}"}

      ${if p.fan-curve == null
        then ''
          # 3. Заводская кривая вентиляторов.
          z13ctl fancurve --reset
        ''
        else ''
          # 3. Кастомная кривая вентиляторов.
          z13ctl fancurve --set "${p.fan-curve}"
        ''}

      echo "[z13-profile] Профиль '${physicalName}' применён."
    '';
  };

  # ---------------------------------------------------------------------
  # ppdSyncScript — слушает изменения ActiveProfile в PPD.
  #
  # Реализация — polling через busctl раз в 2 секунды.
  # Парсинг без awk — используется pure bash (awk нет в PATH сервиса).
  # ---------------------------------------------------------------------
  ppdSyncScript = pkgs.writeShellApplication {
    name = "z13-ppd-sync";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      echo "[z13-ppd-sync] Старт. Слушаю изменения ActiveProfile в PPD."

      LAST_PROFILE=""

      while true; do
        # Читаем текущий профиль PPD.
        # busctl выводит строку вида: s "power-saver"
        # Парсим pure bash — берём содержимое между кавычками.
        RAW=$(busctl --system get-property \
          net.hadess.PowerProfiles \
          /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles \
          ActiveProfile 2>/dev/null || echo "")

        # RAW = 's "power-saver"'
        # Убираем префикс до первой кавычки, потом суффикс от последней.
        CURRENT="''${RAW#*\"}"
        CURRENT="''${CURRENT%\"*}"

        if [ -z "$CURRENT" ]; then
          # PPD недоступен — ждём.
          sleep 2
          continue
        fi

        # Если профиль изменился — применяем.
        if [ "$CURRENT" != "$LAST_PROFILE" ]; then
          echo "[z13-ppd-sync] PPD ActiveProfile = $CURRENT"

          case "$CURRENT" in
            power-saver)
              ${mkApplyProfile "quiet" eco}/bin/z13-apply-quiet
              ;;
            balanced)
              ${mkApplyProfile "balanced" balanced}/bin/z13-apply-balanced
              ;;
            performance)
              ${mkApplyProfile "performance" performance}/bin/z13-apply-performance
              ;;
            *)
              echo "[z13-ppd-sync] Неизвестный профиль: $CURRENT"
              ;;
          esac

          LAST_PROFILE="$CURRENT"
        fi

        sleep 2
      done
    '';
  };

in
{
  # =====================================================================
  # Power-profiles-daemon — backend для виджета батарейки в KDE.
  # =====================================================================
  services.power-profiles-daemon.enable = true;

  # =====================================================================
  # Сервис синхронизации PPD → z13ctl.
  # =====================================================================
  systemd.services.z13-ppd-sync = {
    description = "Sync z13ctl TDP/fan curves with power-profiles-daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    requires = [ "power-profiles-daemon.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${ppdSyncScript}/bin/z13-ppd-sync";
      Restart = "on-failure";
      RestartSec = "5";
      Nice = 10;
    };
  };

  # =====================================================================
  # Ручные команды для отладки.
  # =====================================================================
  # systemctl start z13-apply-eco
  # systemctl start z13-apply-balanced
  # systemctl start z13-apply-performance
  systemd.services.z13-apply-eco = {
    description = "Apply Z13 eco profile (10W, quiet)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "quiet" eco}/bin/z13-apply-quiet";
    };
  };

  systemd.services.z13-apply-balanced = {
    description = "Apply Z13 balanced profile (75W, factory fans)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "balanced" balanced}/bin/z13-apply-balanced";
    };
  };

  systemd.services.z13-apply-performance = {
    description = "Apply Z13 performance profile (93W, aggressive fans)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "performance" performance}/bin/z13-apply-performance";
    };
  };
}
