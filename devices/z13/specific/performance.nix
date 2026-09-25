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
  #   - При PL1 > 75W z13ctl ТРЕБУЕТ кривую с минимум 80% на всех
  #     точках — иначе отказывается применять настройки. Поэтому
  #     для performance мы не задаём кривую, а отдаём её z13ctl
  #     (флаг skip-fan-curve).
  #   - Fan curve: ровно 8 точек "temp:pct%", температуры по возрастанию,
  #     скорости не убывают.
  # =====================================================================

  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "POWER SAVE" (PPD: power-saver)
  # ---------------------------------------------------------------------
  eco = {
    tdp = 10;
    force = false;
    # Тихая кривая: вентиляторы стоят до 60°C, 100% только к 90°C.
    fan-curve = "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "BALANCED" (PPD: balanced)
  # ---------------------------------------------------------------------
  balanced = {
    tdp = 75;
    force = false;
    # null → fancurve --reset (заводская кривая ASUS).
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "PERFORMANCE" (PPD: performance)
  # ---------------------------------------------------------------------
  performance = {
    tdp = 93;
    force = true;
    # При PL1 > 75W z13ctl сам применяет 80%+ кривую для термальной
    # безопасности. Мы не трогаем fan-curve — иначе конфликт.
    skip-fan-curve = true;
  };

  # ---------------------------------------------------------------------
  # mkApplyProfile — генератор скрипта применения одного профиля.
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

      # 3. Кривая вентиляторов.
      ${if (p.skip-fan-curve or false)
        then ''
          # Кривая управляется z13ctl автоматически, т.к. PL1 > 75W.
          echo "[z13-profile] Fan curve: управляется z13ctl (80%+ для термобезопасности)."
        ''
        else if p.fan-curve == null
          then "z13ctl fancurve --reset"
          else "z13ctl fancurve --set \"${p.fan-curve}\""}

      echo "[z13-profile] Профиль '${physicalName}' применён."
    '';
  };

  # ---------------------------------------------------------------------
  # ppdSyncScript — слушает изменения ActiveProfile в PPD.
  # Polling раз в 2 секунды. Парсинг без awk (pure bash).
  # ---------------------------------------------------------------------
  ppdSyncScript = pkgs.writeShellApplication {
    name = "z13-ppd-sync";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      echo "[z13-ppd-sync] Старт. Слушаю изменения ActiveProfile в PPD."

      LAST_PROFILE=""

      while true; do
        # busctl выводит строку вида: s "power-saver"
        RAW=$(busctl --system get-property \
          net.hadess.PowerProfiles \
          /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles \
          ActiveProfile 2>/dev/null || echo "")

        # Парсим pure bash: убираем префикс до первой кавычки,
        # затем суффикс от последней.
        CURRENT="''${RAW#*\"}"
        CURRENT="''${CURRENT%\"*}"

        if [ -z "$CURRENT" ]; then
          sleep 2
          continue
        fi

        if [ "$CURRENT" != "$LAST_PROFILE" ]; then
          echo "[z13-ppd-sync] PPD ActiveProfile = $CURRENT"

          case "$CURRENT" in
            power-saver)
              ${mkApplyProfile "quiet" eco}/bin/z13-apply-quiet || true
              ;;
            balanced)
              ${mkApplyProfile "balanced" balanced}/bin/z13-apply-balanced || true
              ;;
            performance)
              ${mkApplyProfile "performance" performance}/bin/z13-apply-performance || true
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
    description = "Apply Z13 performance profile (93W, z13ctl-managed fans)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "performance" performance}/bin/z13-apply-performance";
    };
  };
}
