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
  #
  # ВАЖНО: `z13ctl tdp --set …` / `fancurve --set …` пишут состояние
  # в EC/ACPI, и оно ПЕРЕЖИВАЕТ смену конфига на Path A (config
  # перестаёт вызывать set, но EC помнит последнее записанное).
  # Отсюда возможное расхождение температур между устройствами:
  # на одном когда-то сработали кастомные set, на другом — нет.
  # Для приведения к одному известному состоянию добавлены
  # `z13ctl init` / `z13ctl-init` — см. ниже.
  #
  # Принцип z13ctl init: писать ТОЛЬКО те значения, которые НЕ
  # превышают заводской PPT (eco=10W, balanced=75W, performance=75W).
  # Именно 90W+force раньше уводил platform_profile в `custom` и
  # ломал F5 — поэтому z13ctl init 90W+force больше НЕ использует.
  # =====================================================================

  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "POWER SAVER" (PPD: power-saver → firmware: quiet)
  # ---------------------------------------------------------------------
  # Default: TDP и кривую вентиляторов выставляет прошивка для quiet.
  # Оригинальный кастом (для справки):
  #   tdp = 10;
  #   fan-curve = "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%";
  # `z13ctl init eco` применяет именно эти значения (10W ниже
  # заводского потолка → platform_profile остаётся normal, F5 циклии).
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
  # `z13ctl init balanced` применяет 75W — ровно заводскую границу,
  # поэтому F5 продолжает циклить.
  balanced = {
    tdp = null;
    force = false;
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "PERFORMANCE" (PPD: performance → firmware: performance)
  # ---------------------------------------------------------------------
  # Default: 75W (без --force) — именно эту границу держит firmware.
  # `z13ctl init performance` применяет profile=performance + tdp=75
  # БЕЗ --force. Это:
  #   * снимает stale-кастом (если на устройстве раньше остался 90W
  #     от ручных экспериментов) — 75W явно перезаписывает EC;
  #   * не выходит за заводской PPT → platform_profile остаётся
  #     normal, F5 продолжает циклить.
  #
  # 90W с флагом --force ОТКЛЮЧАЛО F5: драйвер видел PPT выше заводских
  # и переводил platform_profile в `custom`. Этот вариант сохранён
  # в комментариях ТОЛЬКО для ручного применения через
  #   systemctl start z13-apply-performance
  # после раскомментирования значений — но z13ctl init его НЕ
  # использует.
  # Оригинальный кастом (для справки, ломает F5):
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

  # ---------------------------------------------------------------------
  # z13ctl-init — РУЧНОЕ применение известных значений из комментариев
  # выше (eco/balanced/performance). Одна команда:
  #
  #   z13ctl-init                 # auto: профиль определяется по PPD
  #   z13ctl-init eco             # profile=quiet, tdp=10, кастомная fan-curve
  #   z13ctl-init balanced        # profile=balanced, tdp=75
  #   z13ctl-init performance     # profile=performance, tdp=75 (БЕЗ --force)
  #
  # Зачем: `z13ctl tdp --set …` / `fancurve --set …` пишут состояние в
  # EC/ACPI, и оно переживает смену конфига на Path A. Если на одном
  # устройстве когда-то применялся кастом, а на другом — нет, при
  # одинаковой LLM-нагрузке температуры разойдутся. `z13ctl-init`
  # применяет ОДНИ И ТЕ ЖЕ значения на обоих устройствах → паритет.
  #
  # ПРИНЦИП: пишем только то, что НЕ превышает заводской PPT.
  #   eco=10W (ниже потолка), balanced=75W (ровно потолок),
  #   performance=75W (ровно потолок, БЕЗ --force).
  # Именно поэтому F5 продолжает циклить после любого z13ctl-init:
  # platform_profile не уходит в `custom`.
  #
  # 90W --force больше НЕ используется: он раньше переводил драйвер
  # в `custom` и «залипал» F5. Если очень нужно 90W — только вручную
  # через `systemctl start z13-apply-performance` после раскомменти-
  # рования кастома в let-блоке, понимая, что F5 после этого
  # перестанет циклить до перезагрузки.
  # ---------------------------------------------------------------------
  z13ctl-init = pkgs.writeShellApplication {
    name = "z13ctl-init";
    runtimeInputs = [ z13ctl-plus pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      TARGET="''${1:-auto}"

      if [ "$TARGET" = "auto" ]; then
        RAW=$(busctl --system get-property \
          net.hadess.PowerProfiles \
          /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles \
          ActiveProfile 2>/dev/null || echo "")
        CURRENT="''${RAW#*\"}"
        CURRENT="''${CURRENT%\"*}"
        case "$CURRENT" in
          power-saver) TARGET=eco ;;
          balanced)    TARGET=balanced ;;
          performance) TARGET=performance ;;
          *)
            echo "Не удалось определить PPD ActiveProfile (получено: '$CURRENT')." >&2
            echo "Укажи профиль явно: z13ctl-init {eco|balanced|performance}" >&2
            exit 1
            ;;
        esac
        echo "[z13ctl-init] PPD ActiveProfile = $CURRENT → профиль $TARGET"
      fi

      case "$TARGET" in
        eco)
          # 10W — ниже заводского потолка, кастомная fan-curve не
          # выходит за заводские границы. platform_profile остаётся
          # normal, F5 циклии.
          echo "[z13ctl-init] eco: profile=quiet, tdp=10, кастомная fan-curve"
          z13ctl profile --set quiet
          z13ctl tdp --set 10
          z13ctl fancurve --set "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%"
          ;;
        balanced)
          # 75W — ровно та граница, которую держит firmware для
          # balanced. Явная запись 75W синхронизирует оба устройства
          # (снимает stale-кастом на первом), но НЕ выходит за
          # заводской PPT → platform_profile остаётся normal, F5 циклии.
          echo "[z13ctl-init] balanced: profile=balanced, tdp=75"
          z13ctl profile --set balanced
          z13ctl tdp --set 75
          ;;
        performance)
          # ВАЖНО: 75W БЕЗ --force. Явная запись 75W снимает
          # возможный stale-кастом 90W на первом устройстве, но не
          # выходит за заводской PPT → platform_profile остаётся
          # normal, F5 продолжает циклить.
          # 90W --force больше НЕ используется: именно он раньше
          # переводил драйвер в `custom` и «залипал» F5.
          echo "[z13ctl-init] performance: profile=performance, tdp=75 (без --force)"
          z13ctl profile --set performance
          z13ctl tdp --set 75
          ;;
        *)
          echo "Неизвестный профиль: $TARGET" >&2
          echo "Использование: z13ctl-init [eco|balanced|performance]" >&2
          exit 1
          ;;
      esac

      # Пост-проверка: при значениях выше platform_profile НЕ должен
      # становиться `custom`. Если стал — EC был в неожиданном
      # состоянии, F5 может не циклить. Сообщаем явно.
      PP=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "")
      echo "[z13ctl-init] platform_profile = ''${PP:-<unknown>}"
      if [ "$PP" = "custom" ]; then
        echo "[z13ctl-init] ВНИМАНИЕ: platform_profile=custom — F5 может не циклить." >&2
        echo "[z13ctl-init] Перезагрузи устройство, чтобы вернуть firmware-контроль." >&2
        exit 2
      fi

      echo "[z13ctl-init] Готово. F5 должен продолжать циклить."
    '';
  };

  # ---------------------------------------------------------------------
  # z13ctl-with-init — обёртка над z13ctl, добавляющая `init` как
  # подкоманду. Всё остальное делегируется в оригинальный z13ctl
  # из z13ctl-plus. Нужна, чтобы работала привычная запись
  #   z13ctl init [eco|balanced|performance]
  # при сохранении всех остальных подкоманд (profile, tdp, fancurve).
  #
  # ВАЖНО: эта обёртка — ЕДИНСТВЕННЫЙ z13ctl в PATH (z13ctl-plus
  # не добавлен в environment.systemPackages, он живёт только в
  # runtimeInputs скриптов). Поэтому коллизии имён нет, а все
  # вызовы `z13ctl …` в systemd-сервисах и mkApplyProfile идут
  # через runtimeInputs [ z13ctl-plus ] и получают ОРИГИНАЛЬНЫЙ
  # бинарь напрямую — рекурсии не возникает.
  # ---------------------------------------------------------------------
  z13ctl-with-init = pkgs.writeShellApplication {
    name = "z13ctl";
    runtimeInputs = [ z13ctl-plus z13ctl-init ];
    text = ''
      set -euo pipefail
      if [ "''${1:-}" = "init" ]; then
        shift
        exec z13ctl-init "$@"
      fi
      exec z13ctl "$@"
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

  # =====================================================================
  # z13ctl init — ручное применение известных значений на оба устройства.
  #
  # z13ctl-with-init даёт бинарь `z13ctl` с подкомандой `init`:
  #   z13ctl init                 # auto по PPD ActiveProfile
  #   z13ctl init eco             # profile=quiet, tdp=10, fan-curve
  #   z13ctl init balanced        # profile=balanced, tdp=75
  #   z13ctl init performance     # profile=performance, tdp=75 (без --force)
  #
  # Все три варианта пишут только те значения, которые НЕ превышают
  # заводской PPT → platform_profile остаётся normal, F5 циклии.
  # 90W+force больше НЕ используется: он раньше «залипал» F5.
  #
  # z13ctl-init — та же функциональность как самостоятельный бинарь
  # (удобно для shell-автодополнения и скриптов).
  #
  # ВАЖНО: z13ctl-plus НЕ добавлен сюда, поэтому в PATH ровно один
  # `z13ctl` (обёртка). Скрипты mkApplyProfile/ppdSyncScript берут
  # оригинал через runtimeInputs — рекурсии нет.
  # =====================================================================
  environment.systemPackages = [
    z13ctl-with-init
    z13ctl-init
  ];
}
