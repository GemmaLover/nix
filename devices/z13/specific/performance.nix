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
  # Для приведения к одному известному состоянию используется
  # `z13ctl init308` / `z13ctl init311` — см. ниже.
  #
  # Про BIOS 308 vs 311:
  #   * 308 — заводские PL (quiet 40/55/55, balanced 52/71/70,
  #     performance 70/86/86) и «нормальная» кривая вентиляторов.
  #   * 311 — на форумах жалуются, что EC ленивее повышает обороты
  #     под длительной нагрузкой → те же PL, но выше температуры.
  #
  # `z13ctl init308` — ЗАВОДСКОЙ BASELINE:
  #   Для всех профилей — заводская кривая (baseFanCurves.<profile>),
  #   покопированная из вывода `fancurve --get` на BIOS 308, каждая
  #   дополнена 90:100% для термобезопасности.
  #
  # `z13ctl init311` — КОМПЕНСАЦИЯ BIOS 311:
  #   * quiet       → заводская quiet-кривая + 90:100% (НЕ агрессивная:
  #                   в тихом режиме агрессивная слишком шумная, а PL
  #                   40/55/55 и так низкие);
  #   * balanced    → агрессивная кривая + 90:100%;
  #   * performance → агрессивная кривая + 90:100%.
  #   TDP НЕ трогаем — оставляем заводские PL для текущего профиля.
  #
  # ПОБОЧНЫЙ ЭФФЕКТ: раз init308/init311 пишут fancurve, вентиляторы
  # переходят в custom mode (pwm_enable=1). После этого F5 меняет
  # только platform_profile (TDP), но НЕ обороты вентиляторов — они
  # идут строго по нашей кривой. Чтобы вернуть F5-контроль над
  # вентиляторами — ребут (EC вернёт свои дефолты).
  # =====================================================================

  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # Базовые кривые вентиляторов — покопированы из вывода
  # `z13ctl fancurve --get` на BIOS 308 (эталонное устройство), каждая
  # дополнена точкой 90:100% для термобезопасности.
  #
  # Зачем 90:100%: заводские кривые плато на ~40-57% до 76-80°C, и
  # при BIOS 311 EC может не успеть раскрутить вентиляторы до
  # максимума до того, как APU упрётся в троттлинг. Точка 90:100%
  # гарантирует, что к 90°C вентиляторы выходят на 100%, независимо
  # от профиля.
  #
  # Эти кривые используются в `z13ctl init308` (все профили) и в
  # `z13ctl init311` для профиля quiet.
  # ---------------------------------------------------------------------
  baseFanCurves = {
    # из `z13ctl fancurve --get` на BIOS 308, профиль power-saver/quiet:
    # 50:0%, 54:0%, 58:8%, 62:11%, 64:16%, 67:21%, 71:26%, 71:26%
    quiet = "50:0%,54:0%,58:8%,62:11%,64:16%,67:21%,71:26%,90:100%";

    # из `z13ctl fancurve --get` на BIOS 308, профиль balanced:
    # 48:0%, 53:8%, 57:11%, 60:16%, 63:21%, 65:26%, 70:34%, 76:40%
    balanced = "48:0%,53:8%,57:11%,60:16%,63:21%,65:26%,70:34%,76:40%,90:100%";

    # из `z13ctl fancurve --get` на BIOS 308, профиль performance:
    # 42:11%, 50:21%, 55:26%, 60:33%, 65:36%, 70:44%, 75:51%, 80:57%
    performance = "42:11%,50:21%,55:26%,60:33%,65:36%,70:44%,75:51%,80:57%,90:100%";
  };

  # ---------------------------------------------------------------------
  # Агрессивная кривая — компенсация «ленивого» EC на BIOS 311.
  # Примерно в 1.5–2 раза выше по PWM в рабочем диапазоне, чем
  # заводская balanced. Точка 90:100% — та же термобезопасность,
  # что и в базовых кривых.
  #
  # Используется в `z13ctl init311` для профилей balanced и
  # performance. Для quiet остаётся заводская кривая (агрессивная
  # в тихом режиме слишком шумная, а PL 40/55/55 и так низкие).
  #
  # Крути по вкусу, но держи монотонность по температуре. Если стало
  # слишком шумно — сдвинь точки на +3-5°C или урежь проценты.
  # ---------------------------------------------------------------------
  aggressiveFanCurve = "50:10%,55:20%,60:35%,65:50%,70:70%,75:85%,80:95%,90:100%";

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
  # и переводил platform_profile в `custom`. Этот вариант сохранён
  # в комментариях ТОЛЬКО для ручного применения через
  #   systemctl start z13-apply-performance
  # после раскомментирования значений — но z13ctl-init его НЕ
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
  # z13ctl-init — приведение устройства к одному из двух известных
  # состояний. TDP НЕ трогаем — оставляем заводские PL для текущего
  # профиля. Крутим только вентиляторы.
  #
  #   z13ctl-init 308   (или base)
  #     Заводская кривая вентиляторов для текущего профиля
  #     (baseFanCurves.<profile>) + 100% на 90°C.
  #     Плюс `z13ctl profile --set <phys>` — чтобы firmware применил
  #     свои PL для этого профиля.
  #     Используй: как «здоровый» baseline, паритет с первым
  #     устройством на BIOS 308.
  #
  #   z13ctl-init 311   (или aggressive)
  #     Заводские PL + кривая вентиляторов:
  #       quiet       → baseFanCurves.quiet       (заводская + 90:100%)
  #       balanced    → aggressiveFanCurve         (агрессивная + 90:100%)
  #       performance → aggressiveFanCurve         (агрессивная + 90:100%)
  #     Для quiet агрессивная не используется: PL 40/55/55 и так
  #     низкие, а агрессивная кривая в тихом режиме слишком шумная.
  #     Используй: на втором устройстве с BIOS 311, если температуры
  #     выше, чем на первом (308) при одинаковых PL.
  #
  # ВНИМАНИЕ: обе подкоманды пишут fancurve → вентиляторы переходят
  # в custom mode (pwm_enable=1). После этого F5 меняет только
  # platform_profile (TDP), но НЕ обороты вентиляторов — они идут
  # строго по нашей кривой. Чтобы вернуть F5-контроль над
  # вентиляторами — ребут (EC вернёт свои дефолты).
  # ---------------------------------------------------------------------
  z13ctl-init = pkgs.writeShellApplication {
    name = "z13ctl-init";
    runtimeInputs = [ z13ctl-plus pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      MODE="''${1:-308}"

      # ── Определение текущего профиля PPD → physical ────────────
      detect_phys() {
        local raw cur
        raw=$(busctl --system get-property \
          net.hadess.PowerProfiles \
          /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles \
          ActiveProfile 2>/dev/null || echo "")
        cur="''${raw#*\"}"
        cur="''${cur%\"*}"
        case "$cur" in
          power-saver) echo "quiet" ;;
          balanced)    echo "balanced" ;;
          performance) echo "performance" ;;
          *) return 1 ;;
        esac
      }

      PHYS=$(detect_phys) || {
        echo "[z13ctl-init] Не удалось определить PPD ActiveProfile." >&2
        echo "[z13ctl-init] Убедись, что power-profiles-daemon запущен." >&2
        exit 1
      }
      echo "[z13ctl-init] PPD active → physical profile: $PHYS"

      # Кривая по профилю для базового режима (308).
      case "$PHYS" in
        quiet)       BASE_CURVE="${baseFanCurves.quiet}" ;;
        balanced)    BASE_CURVE="${baseFanCurves.balanced}" ;;
        performance) BASE_CURVE="${baseFanCurves.performance}" ;;
      esac

      # ── Режимы ──────────────────────────────────────────────────
      case "$MODE" in
        308|base)
          # Заводские PL через profile --set + заводская кривая
          # (по профилю) + 100% на 90°C.
          echo "[z13ctl-init308] Заводские PL + заводская кривая + 100% на 90°C."
          z13ctl profile --set "$PHYS"
          echo "[z13ctl-init308] fancurve ($PHYS): $BASE_CURVE"
          z13ctl fancurve --set "$BASE_CURVE"
          ;;

        311|aggressive)
          # Заводские PL + кривая, зависящая от профиля:
          #   quiet       → заводская quiet + 90:100%
          #   balanced    → агрессивная + 90:100%
          #   performance → агрессивная + 90:100%
          z13ctl profile --set "$PHYS"
          if [ "$PHYS" = "quiet" ]; then
            echo "[z13ctl-init311] quiet → заводская кривая + 90:100%"
            echo "[z13ctl-init311] fancurve: $BASE_CURVE"
            z13ctl fancurve --set "$BASE_CURVE"
          else
            echo "[z13ctl-init311] $PHYS → агрессивная кривая + 90:100%"
            echo "[z13ctl-init311] fancurve: ${aggressiveFanCurve}"
            z13ctl fancurve --set "${aggressiveFanCurve}"
          fi
          ;;

        *)
          echo "[z13ctl-init] Неизвестный режим: $MODE" >&2
          echo "[z13ctl-init] Использование: z13ctl init {308|311}" >&2
          echo "[z13ctl-init]   308 (base)       — заводская кривая (по профилю) + 90:100%" >&2
          echo "[z13ctl-init]   311 (aggressive) — quiet: заводская; balanced/perf: агрессивная; + 90:100%" >&2
          exit 1
          ;;
      esac

      # ── Пост-проверка ───────────────────────────────────────────
      echo
      echo "--- TDP ---"
      z13ctl tdp --get || true
      echo "--- Fans ---"
      z13ctl fancurve --get || true
      PP=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "")
      echo "--- platform_profile: ''${PP:-<unknown>} ---"

      if [ "$PP" = "custom" ]; then
        echo "[z13ctl-init] ВНИМАНИЕ: platform_profile=custom — F5 может не циклить." >&2
        echo "[z13ctl-init] Это ожидаемо после записи fancurve; для полного сброса — reboot." >&2
      fi

      echo "[z13ctl-init] Готово."
    '';
  };

  # ---------------------------------------------------------------------
  # z13ctl-with-init — обёртка над z13ctl, добавляющая `init`, `init308`,
  # `init311` как подкоманды. Всё остальное делегируется в оригинальный
  # z13ctl из z13ctl-plus. Нужна, чтобы работали привычные записи:
  #   z13ctl init308
  #   z13ctl init311
  #   z13ctl init 308
  #   z13ctl init 311
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
      case "''${1:-}" in
        init)    shift; exec z13ctl-init "$@" ;;
        init308) shift; exec z13ctl-init 308 ;;
        init311) shift; exec z13ctl-init 311 ;;
        *)       exec z13ctl "$@" ;;
      esac
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
  # ЧТОБЫ ВЕРНУТЬ КАСТОМ:
  #   1. Раскомментируйте tdp/fan-curve в eco/balanced/performance выше.
  #   2. Раскомментируйте блок ниже.
  #   3. Пересоберите систему.
  # =====================================================================
  # systemd.services.z13-ppd-sync = {
  #   description = "Sync z13ctl TDP/fan curves with power-profiles-daemon";
  #
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
  # =====================================================================
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
  # z13ctl init308 / init311 — приведение к известному состоянию.
  #
  #   z13ctl init308   — заводская кривая для текущего профиля
  #                      (baseFanCurves) + 100% на 90°C.
  #   z13ctl init311   — quiet: заводская кривая + 100% на 90°C;
  #                      balanced/performance: агрессивная кривая +
  #                      100% на 90°C. TDP не трогаем.
  #
  # Также работают: z13ctl init 308, z13ctl init 311.
  #
  # ВАЖНО: z13ctl-plus НЕ добавлен сюда, в PATH ровно один
  # `z13ctl` (обёртка). Скрипты mkApplyProfile/ppdSyncScript берут
  # оригинал через runtimeInputs — рекурсии нет.
  # =====================================================================
  environment.systemPackages = [
    z13ctl-with-init
    z13ctl-init
  ];
}
