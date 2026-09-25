{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ПРОФИЛИ ПРОИЗВОДИТЕЛЬНОСТИ ASUS ROG FLOW Z13 (GZ302EA)
  #
  # Меняйте значения в блоках balanced / eco / performance ниже —
  # они применятся при следующем nixos-rebuild.
  #
  # ВАЖНО: точный синтаксис команд z13ctl может отличаться.
  # Проверьте перед изменением:
  #   z13ctl tdp --help
  #   z13ctl fancurve --help
  #   z13ctl profile --help
  # =====================================================================

  # z13ctl-plus — локальный пакет из pkgs/. Подключаем так же, как в
  # devices/z13/specific/z13-tools.nix.
  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };

  # ---------------------------------------------------------------------
  # ОБЩИЕ НАСТРОЙКИ
  # ---------------------------------------------------------------------

  # Максимальная температура, выше которой система throttling.
  # z13ctl пока не имеет прямой команды для этого лимита;
  # значение зарезервировано для будущего использования.
  max-temp = 90;

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ BALANCED (по умолчанию при питании от сети)
  # ---------------------------------------------------------------------
  balanced = {
    # TDP для CPU+GPU в ваттах. 85W — компромисс между производительностью
    # и нагревом. Разница с 120W даёт всего 5–7% производительности.
    tdp = 85;
    # fan-curve не задаём — используем заводскую кривую ASUS.
    # Если хотите свою, раскомментируйте и настройте:
    # fan-curve = "45:0,50:10,55:20,60:35,65:50,70:70,75:90,80:100";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ ECO (автоматически при питании от батареи)
  # ---------------------------------------------------------------------
  eco = {
    # Очень низкий лимит — maximise время автономной работы.
    tdp = 10;
    # Тихая кривая: 30% на 60°C, 100% на 80°C.
    fan-curve = "45:0,50:5,55:15,60:30,65:45,70:65,75:85,80:100";
  };

  # ---------------------------------------------------------------------
  # ПРОФИЛЬ PERFORMANCE (только вручную)
  # ---------------------------------------------------------------------
  performance = {
    # Высокий лимит для тяжёлых задач (LLM, компиляция, игры).
    tdp = 100;
    # Агрессивная кривая: 100% на 75°C.
    fan-curve = "45:0,50:15,55:30,60:50,65:70,70:85,75:100,80:100";
  };

  # ---------------------------------------------------------------------
  # Автоматическое переключение
  # ---------------------------------------------------------------------
  # При питании от батареи → eco, при подключении к сети → balanced.
  # Performance включается только вручную.
  # ---------------------------------------------------------------------

  # Функция, генерирующая shell-скрипт для применения профиля.
  # Возвращает путь к скрипту, который можно использовать в ExecStart.
  mkApplyProfile = name: profile: pkgs.writeShellScript "z13-apply-${name}" ''
    set -euo pipefail
    echo "[z13-profile] Применяю профиль '${name}'..."

    # Устанавливаем TDP.
    # Синтаксис уточните: z13ctl tdp --help
    ${z13ctl-plus}/bin/z13ctl tdp set ${toString profile.tdp} || \
      echo "[z13-profile] tdp set вернул ошибку, проверьте синтаксис"

    ${lib.optionalString (profile ? fan-curve) ''
      # Устанавливаем кривую вентиляторов.
      # Синтаксис уточните: z13ctl fancurve --help
      ${z13ctl-plus}/bin/z13ctl fancurve set "${profile.fan-curve}" || \
        echo "[z13-profile] fancurve set вернул ошибку, проверьте синтаксис"
    ''}

    echo "[z13-profile] Профиль '${name}' применён."
  '';

  # Определение источника питания (AC или батарея).
  mkDetectPower = ''
    if [ -d /sys/class/power_supply/AC0 ] || [ -d /sys/class/power_supply/AC ]; then
      # Есть AC-адаптер. Проверяем, подключён ли он.
      AC_ONLINE=$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1 || echo 0)
      if [ "$AC_ONLINE" = "1" ]; then
        echo "ac"
      else
        echo "battery"
      fi
    else
      echo "battery"
    fi
  '';

in
{
  # =====================================================================
  # Пакеты
  # =====================================================================
  # z13ctl-plus уже подключён в z13-tools.nix, дублировать не нужно.
  # Здесь добавляем только то, чего там нет.
  # (Ничего не добавляем.)

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
        ${mkDetectPower}

        SOURCE=$(detect_power 2>/dev/null || echo "battery")
        # Переопределяем функцию: execute выводит только "ac"/"battery"
        # на основе глобальной переменной, но проще переписать inline:
        if [ -d /sys/class/power_supply/AC0 ] || [ -d /sys/class/power_supply/AC ]; then
          AC_ONLINE=$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1 || echo 0)
          if [ "$AC_ONLINE" = "1" ]; then SOURCE="ac"; else SOURCE="battery"; fi
        else
          SOURCE="battery"
        fi

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

  # Udev-правило: перезапускать сервис при изменении состояния питания.
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
    description = "Apply Z13 Eco profile";
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
