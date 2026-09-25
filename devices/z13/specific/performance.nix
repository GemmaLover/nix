{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ПРОФИЛИ ПРОИЗВОДИТЕЛЬНОСТИ ASUS ROG FLOW Z13 (GZ302EA)
  #
  # Меняйте значения в блоках balanced / eco / performance —
  # они применятся при следующем nixos-rebuild.
  #
  # Ограничения железа:
  #   - PL1 (sustained TDP): максимум 93W с флагом --force.
  #     Без --force ядро ограничивает PL1 до 75W.
  #   - Если PL1 > 75W, вентиляторы временно фиксируются на 80%+ для
  #     термальной безопасности (это делает сам z13ctl).
  #   - Fan curve: ровно 8 точек "temp:pct%", температуры по возрастанию,
  #     скорости не убывают.
  # =====================================================================

  # z13ctl-plus — локальный пакет из pkgs/.
  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ОБЩИЕ НАСТРОЙКИ
  # ---------------------------------------------------------------------

  # Максимальная температура, выше которой система должна throttling.
  # ПРИМЕЧАНИЕ: z13ctl пока не имеет команды для этого лимита — он
  # контролируется firmware/ядром. Значение оставлено для документации.
  max-temp = 90;

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ BALANCED (по умолчанию при питании от сети)
  # ---------------------------------------------------------------------
  balanced = {
    # Имя физического профиля в z13ctl (quiet | balanced | performance).
    profile = "balanced";

    # TDP: 75W — безопасный максимум без --force.
    # Если хотите 85W, поставьте force = true ниже.
    tdp = 75;

    # Применять ли --force для PL1 > 75W.
    # false — максимум 75W.
    # true  — до 93W, но вентиляторы временно фиксируются на 80%+.
    force = false;

    # Кулеры: не задаём — используется заводская кривая ASUS.
    # Если хотите свою, раскомментируйте и настройте:
    # fan-curve = "45:0%,50:10%,55:20%,60:35%,65:50%,70:70%,75:90%,80:100%";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ ECO (автоматически при питании от батареи)
  # ---------------------------------------------------------------------
  eco = {
    # z13ctl использует имя "quiet" для тихого/энергосберегающего режима.
    profile = "quiet";

    # TDP: 10W — минимум для maximise автономности.
    tdp = 10;

    # 10W ниже 75W — --force не нужен.
    force = false;

    # Тихая кривая: 30% на 60°C, 100% на 80°C.
    fan-curve = "45:0%,50:5%,55:15%,60:30%,65:45%,70:65%,75:85%,80:100%";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ PERFORMANCE (только вручную)
  # ---------------------------------------------------------------------
  performance = {
    profile = "performance";

    # 93W — физический максимум для GZ302EA. Требует --force.
    tdp = 90;
    force = true;

    # Агрессивная кривая: 100% на 75°C.
    fan-curve = "45:0%,50:15%,55:30%,60:50%,65:70%,70:85%,75:100%,80:100%";
  };

  # ---------------------------------------------------------------------
  # Автопереключение: батарея → eco, сеть → balanced.
  # Performance включается только вручную.
  # ---------------------------------------------------------------------

  # Генерирует shell-скрипт для применения профиля.
  mkApplyProfile = name: p: pkgs.writeShellScript "z13-apply-${name}" ''
    set -euo pipefail
    echo "[z13-profile] Применяю профиль '${name}'..."

    # 1. Физический профиль (quiet | balanced | performance).
    ${z13ctl-plus}/bin/z13ctl profile --set ${p.profile}

    # 2. TDP.
    ${if p.force
      then "${z13ctl-plus}/bin/z13ctl tdp --set ${toString p.tdp} --force"
      else "${z13ctl-plus}/bin/z13ctl tdp --set ${toString p.tdp}"}

    ${lib.optionalString (p ? fan-curve) ''
      # 3. Кривая вентиляторов.
      ${z13ctl-plus}/bin/z13ctl fancurve --set "${p.fan-curve}"
    ''}

    echo "[z13-profile] Профиль '${name}' применён."
  '';

  # Определение источника питания.
  mkDetectPower = pkgs.writeShellScript "z13-detect-power" ''
    if [ -d /sys/class/power_supply/AC0 ] || [ -d /sys/class/power_supply/AC ]; then
      AC_ONLINE=$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1 || echo 0)
      if [ "$AC_ONLINE" = "1" ]; then echo "ac"; else echo "battery"; fi
    else
      echo "battery"
    fi
  '';

in
{
  # =====================================================================
  # Автопереключение профилей при смене источника питания
  # =====================================================================
  systemd.services.z13-auto-profile = {
    description = "Auto-switch Z13 power profile based on power source";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "z13-auto-profile" ''
        set -euo pipefail
        SOURCE=$(${mkDetectPower})

        if [ "$SOURCE" = "ac" ]; then
          echo "[z13-auto-profile] Питание от сети → balanced"
          ${mkApplyProfile "balanced" balanced}
        else
          echo "[z13-auto-profile] Питание от батареи → eco"
          ${mkApplyProfile "eco" eco}
        fi
      '';
    };
  };

  # Udev: перезапускать сервис при изменении состояния питания.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ACTION=="change", TAG+="systemd", ENV{SYSTEMD_WANTS}="z13-auto-profile.service"
  '';

  # =====================================================================
  # Ручное переключение профилей
  # =====================================================================
  # Использование:
  #   sudo systemctl start z13-profile-balanced
  #   sudo systemctl start z13-profile-eco
  #   sudo systemctl start z13-profile-performance
  systemd.services.z13-profile-balanced = {
    description = "Apply Z13 Balanced profile";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "balanced" balanced;
    };
  };

  systemd.services.z13-profile-eco = {
    description = "Apply Z13 Eco (quiet) profile";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "eco" eco;
    };
  };

  systemd.services.z13-profile-performance = {
    description = "Apply Z13 Performance profile";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkApplyProfile "performance" performance;
    };
  };
}
