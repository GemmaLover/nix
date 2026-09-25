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
  # Автоматически включается при работе от батареи (если так настроено
  # в System Settings → Power Management KDE).
  eco = {
    tdp = 10;
    force = false;
    # Очень тихая кривая: вентиляторы стоят до 60°C, 100% только к 90°C.
    # z13ctl использует проценты с суффиксом %.
    fan-curve = "55:0%,60:0%,65:8%,70:18%,75:35%,80:60%,85:85%,90:100%";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "BALANCED" — соответствует balanced в PPD
  # ---------------------------------------------------------------------
  # Автоматически включается при подключении к сети (если так настроено).
  balanced = {
    # 75W — безопасный максимум без --force.
    tdp = 75;
    force = false;
    # Заводская кривая ASUS.
    fan-curve = null;
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ "PERFORMANCE" — соответствует performance в PPD
  # ---------------------------------------------------------------------
  # Включается вручную через виджет KDE.
  performance = {
    # 93W — физический максимум GZ302EA. Требует --force.
    tdp = 93;
    force = true;
    # Агрессивная кривая: 100% на 75°C.
    fan-curve = "45:0%,50:15%,55:30%,60:50%,65:70%,70:85%,75:100%,80:100%";
  };

  # ---------------------------------------------------------------------
  # Вспомогательная функция: сгенерировать shell-скрипт применения
  # одного профиля. Используется и в ppd-sync, и при ручном вызове.
  # ---------------------------------------------------------------------
  mkApplyProfile = physicalName: p: pkgs.writeShellScript "z13-apply-${physicalName}" ''
    set -euo pipefail
    echo "[z13-profile] Применяю профиль '${physicalName}'..."

    # 1. Физический профиль (quiet | balanced | performance).
    ${z13ctl-plus}/bin/z13ctl profile --set ${physicalName}

    # 2. TDP.
    ${if p.force
      then "${z13ctl-plus}/bin/z13ctl tdp --set ${toString p.tdp} --force"
      else "${z13ctl-plus}/bin/z13ctl tdp --set ${toString p.tdp}"}

    ${if p.fan-curve == null
      then ''
        # 3. Заводская кривая вентиляторов.
        ${z13ctl-plus}/bin/z13ctl fancurve --reset
      ''
      else ''
        # 3. Кастомная кривая вентиляторов.
        ${z13ctl-plus}/bin/z13ctl fancurve --set "${p.fan-curve}"
      ''}

    echo "[z13-profile] Профиль '${physicalName}' применён."
  '';

  # ---------------------------------------------------------------------
  # Скрипт-синхронизатор с power-profiles-daemon.
  #
  # PPD предоставляет три профиля через D-Bus:
  #   power-saver  → eco
  #   balanced     → balanced
  #   performance  → performance
  #
  # Реализация — polling через busctl раз в 2 секунды. Это проще и
  # надёжнее, чем парсинг dbus-monitor, и нагрузка минимальна.
  # ---------------------------------------------------------------------
  ppdSyncScript = pkgs.writeShellScript "z13-ppd-sync" ''
    set -euo pipefail

    echo "[z13-ppd-sync] Старт. Слушаю изменения ActiveProfile в PPD."

    LAST_PROFILE=""

    while true; do
      # Читаем текущий профиль PPD.
      # Формат вывода busctl: s "power-saver"
      CURRENT=$(${pkgs.systemd}/bin/busctl --system get-property \
        net.hadess.PowerProfiles \
        /net/hadess/PowerProfiles \
        net.hadess.PowerProfiles \
        ActiveProfile 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")

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
            ${mkApplyProfile "quiet" eco}
            ;;
          balanced)
            ${mkApplyProfile "balanced" balanced}
            ;;
          performance)
            ${mkApplyProfile "performance" performance}
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

in
{
  # =====================================================================
  # Power-profiles-daemon — backend для виджета батарейки в KDE.
  # =====================================================================
  # Именно PPD показывает профили в трее. KDE общается с ним по D-Bus.
  services.power-profiles-daemon.enable = true;

  # =====================================================================
  # Сервис синхронизации PPD → z13ctl.
  # =====================================================================
  # Слушает ActiveProfile в PPD и применяет TDP + кулеры через z13ctl.
  systemd.services.z13-ppd-sync = {
    description = "Sync z13ctl TDP/fan curves with power-profiles-daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    requires = [ "power-profiles-daemon.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = ppdSyncScript;
      Restart = "on-failure";
      RestartSec = "5";

      # Ограничиваем нагрузку — polling раз в 2 секунды.
      Nice = 10;
    };
  };

  # =====================================================================
  # Ручные команды для отладки (не для повседневного использования).
  # =====================================================================
  # Из терминала:
  #   systemctl start z13-apply-eco
  #   systemctl start z13-apply-balanced
  #   systemctl start z13-apply-performance
  #
  # Но обычно профиль переключается через виджет KDE — эти сервисы
  # нужны только если хотите применить профиль в обход PPD.
  systemd.services.z13-apply-eco = {
    description = "Apply Z13 eco profile (10W, quiet)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "quiet" eco;
    };
  };

  systemd.services.z13-apply-balanced = {
    description = "Apply Z13 balanced profile (75W, factory fans)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "balanced" balanced;
    };
  };

  systemd.services.z13-apply-performance = {
    description = "Apply Z13 performance profile (93W, aggressive fans)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "performance" performance;
    };
  };

  # =====================================================================
  # Демон z13ctld.
  # =====================================================================
  # Раньше был отключён из-за конфликта с белой подсветкой клавиатуры.
  # Если хотите, чтобы кастомные TDP и кривые сохранялись между
  # переключениями профилей (ядро иногда сбрасывает их), раскомментируйте.
  # ВНИМАНИЕ: если подсветка снова станет красной — закомментируйте.
  #
  # systemd.user.services.z13ctld = {
  #   description = "z13ctl-plus daemon for ASUS ROG Flow Z13";
  #   partOf = [ "graphical-session.target" ];
  #   after = [ "graphical-session.target" ];
  #   wantedBy = [ "graphical-session.target" ];
  #   serviceConfig = {
  #     Type = "simple";
  #     ExecStart = "${z13ctl-plus}/bin/z13ctld --no-lighting";
  #     Restart = "on-failure";
  #     RestartSec = "5";
  #   };
  # };
}
