{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ПРОФИЛИ ПРОИЗВОДИТЕЛЬНОСТИ ASUS ROG FLOW Z13 (GZ302EA)
  #
  # Смена парадигмы (Path A): профили ТЕПЕРЬ ведёт прошивка через
  # asus-nb-wmi при нажатии F5. Наш конфиг НЕ переопределяет TDP
  # и кривые вентиляторов — иначе драйвер помечает
  # platform_profile как `custom` и F5 «залипает» после 1-2 нажатий
  # (проверено диагностикой: dmesg показывает
  #  «asus-nb-wmi: Using throttle_thermal_policy for platform_profile
  #   support», а cat /sys/firmware/acpi/platform_profile после F5
  #   уходил в `custom`).
  #
  # Управление идёт по цепочке:
  #   F5  →  firmware  →  platform_profile  (quiet/balanced/performance)
  #        →  firmware применяет свой TDP и свою кривую вентиляторов
  #
  # `z13-ppd-sync` ОТКЛЮЧЁН — при Path A ему нечего синхронизировать.
  # Ручные команды `z13-apply-*` оставлены для отладки и кастомных
  # сценариев (см. systemd.services ниже).
  #
  # ОРИГИНАЛЬНЫЙ КАСТОМ сохранён в комментариях: чтобы вернуть его,
  # раскомментируйте значения в eco/balanced/performance и снова
  # включите systemd.services.z13-ppd-sync.
  # =====================================================================

  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "POWER SAVER" (PPD: power-saver → firmware: quiet)
  # ---------------------------------------------------------------------
  # Default: TDP и кривую вентиляторов выставляет прошивка для quiet.
  # Оригинальный кастом (для справки):
  #   tdp = 10;
  #   fan-curve = "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%";
  eco = {
    tdp = null;
    force = false;
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "BALANCED" (PPD: balanced → firmware: balanced)
  # ---------------------------------------------------------------------
  # Default: 75W + заводская кривая вентиляторов от прошивки.
  # Оригинальный кастом (для справки):
  #   tdp = 75;
  #   fan-curve = null;
  balanced = {
    tdp = null;
    force = false;
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "PERFORMANCE" (PPD: performance → firmware: performance)
  # ---------------------------------------------------------------------
  # Default: 75W (без --force) — именно эту границу держит firmware.
  # 90W с флагом --force ОТКЛЮЧАЛО F5: драйвер видел PPT выше заводских
  # и переводил platform_profile в `custom`. Кастом сохранён в
  # комментариях для ручного применения через
  #   systemctl start z13-apply-performance
  # после раскомментирования значений.
  # Оригинальный кастом (для справки):
  #   tdp = 90;
  #   force = true;
  #   skip-fan-curve = true;
  performance = {
    tdp = null;
    force = false;
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # mkApplyProfile — генератор скрипта применения одного профиля.
  #
  # Логика изменена под Path A:
  #   * `z13ctl profile --set <name>` — всегда (это официальный
  #     интерфейс записи в platform_profile, конфликта с F5 нет);
  #   * `z13ctl tdp --set ...` — ТОЛЬКО если p.tdp задан явно
  #     (в Path A = null, поэтому команда не вызывается);
  #   * `z13ctl fancurve --set ...` — ТОЛЬКО если p.fan-curve задан;
  #   * skip-fan-curve — печатает сообщение, если флаг выставлен.
  #
  # lib.optionalString используется, чтобы избежать «z13ctl tdp --set
  #  --force» при p.tdp = null (toString null = "" — команда ломается).
  # ---------------------------------------------------------------------
  mkApplyProfile = physicalName: p: pkgs.writeShellApplication {
    name = "z13-apply-${physicalName}";
    runtimeInputs = [ z13ctl-plus ];
    text = ''
      set -euo pipefail
      echo "[z13-profile] Применяю профиль '${physicalName}'..."

      # 1. Физический профиль (quiet | balanced | performance).
      #    Это официальный путь записи в platform_profile; firmware
      #    сам применит свой TDP и свою кривую вентиляторов.
      z13ctl profile --set ${physicalName}

      # 2. TDP — только если задан явно в конфиге (Path A: не задан).
      ${lib.optionalString ((p.tdp or null) != null) ''
        ${if p.force or false
          then "z13ctl tdp --set ${toString p.tdp} --force"
          else "z13ctl tdp --set ${toString p.tdp}"}
      ''}

      # 3. Кривая вентиляторов — только если задана явно.
      ${lib.optionalString ((p.fan-curve or null) != null) ''
        z13ctl fancurve --set "${p.fan-curve}"
      ''}
      ${lib.optionalString (p.skip-fan-curve or false) ''
        echo "[z13-profile] Fan curve: управляется z13ctl (80%+ для термобезопасности)."
      ''}

      echo "[z13-profile] Профиль '${physicalName}' применён."
    '';
  };

  # ---------------------------------------------------------------------
  # ppdSyncScript — слушает изменения ActiveProfile в PPD.
  #
  # В Path A сервис ОТКЛЮЧЁН (см. systemd.services.z13-ppd-sync ниже),
  # потому что синхронизировать нечего: firmware сам применяет TDP
  # при смене platform_profile. Скрипт оставлен для случая, когда
  # пользователь захочет вернуть кастомные TDP/кривые.
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
  # Power-profiles-daemon — backend для CLI (powerprofilesctl) и
  # виджетов (Noctalia PPD). Сам по себе PPD НЕ конфликтует с F5:
  # он только читает/пишет platform_profile через штатный интерфейс.
  # Конфликт создавал z13-ppd-sync, который перезаписывал TDP поверх
  # firmware → platform_profile=custom → F5 залипал.
  # =====================================================================
  services.power-profiles-daemon.enable = true;

  # =====================================================================
  # z13-ppd-sync — ОТКЛЮЧЁН (Path A).
  #
  # Причина: при стандартных профилях (без кастомных TDP/кривых)
  # firmware сам применяет правильные TDP и кривую вентиляторов
  # при смене platform_profile. Сервис-синхронизатор не нужен и
  # только создаёт race condition.
  #
  # ЧТОБЫ ВЕРНУТЬ КАСТОМ:
  #   1. Раскомментируйте tdp/fan-curve в eco/balanced/performance выше.
  #   2. Раскомментируйте блок ниже.
  #   3. Пересоберите систему.
  # =====================================================================
  # systemd.services.z13-ppd-sync = {
  #   description = "Sync z13ctl TDP/fan curves with power-profiles-daemon";
  #
  #   # Мягкая привязка к графической сессии.
  #   wantedBy = [ "graphical.target" ];
  #   after = [ "graphical.target" "power-profiles-daemon.service" ];
  #   wants = [ "power-profiles-daemon.service" ];
  #   partOf = [ "graphical.target" ];
  #
  #   serviceConfig = {
  #     Type = "simple";
  #     ExecStart = "${ppdSyncScript}/bin/z13-ppd-sync";
  #     Restart = "on-failure";
  #     RestartSec = "5";
  #     Nice = 10;
  #   };
  # };

  # =====================================================================
  # Ручные команды для отладки.
  #
  # При Path A они применяют ТОЛЬКО profile (без TDP/fancurve).
  # Если раскомментировать кастомные значения в let-блоке — они
  # применят и кастомный TDP (ручной вызов, не через F5).
  # =====================================================================
  # systemctl start z13-apply-eco
  # systemctl start z13-apply-balanced
  # systemctl start z13-apply-performance
  systemd.services.z13-apply-eco = {
    description = "Apply Z13 eco profile (firmware default, quiet)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "quiet" eco}/bin/z13-apply-quiet";
    };
  };

  systemd.services.z13-apply-balanced = {
    description = "Apply Z13 balanced profile (firmware default)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "balanced" balanced}/bin/z13-apply-balanced";
    };
  };

  systemd.services.z13-apply-performance = {
    description = "Apply Z13 performance profile (firmware default, 75W)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkApplyProfile "performance" performance}/bin/z13-apply-performance";
    };
  };
}
