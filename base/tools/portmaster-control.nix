{ config, pkgs, ... }:

let
  # =====================================================================
  # Скрипты для управления Portmaster core (демон).
  #
  # Сам Portmaster установлен через services.portmaster
  # (официальный модуль из nixpkgs-unstable) — он поднимает
  # systemd-сервис portmaster.service.
  #
  # Эти скрипты дают удобные команды для запуска/остановки/перезапуска
  # ядра без ручного ввода systemctl, а также ярлык в меню KDE.
  #
  # ВАЖНО: portmaster.service — системный (не user). Поэтому
  # команды требуют root. В ярлыке используется pkexec, чтобы KDE
  # запрашивал пароль через графический диалог polkit.
  # =====================================================================

  # --- Запуск ядра ---
  portmasterStart = pkgs.writeShellApplication {
    name = "portmaster-start-core";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail

      # Проверяем, что сервис существует.
      if ! systemctl list-unit-files portmaster.service >/dev/null 2>&1; then
        echo "Сервис portmaster.service не найден." >&2
        echo "Убедитесь, что services.portmaster.enable = true в конфиге." >&2
        exit 1
      fi

      # Проверяем, не запущен ли уже.
      STATUS=$(systemctl is-active portmaster.service 2>/dev/null || echo "inactive")
      if [ "$STATUS" = "active" ]; then
        echo "Portmaster уже запущен."
        exit 0
      fi

      echo "Запускаю Portmaster..."
      sudo systemctl start portmaster.service

      # Ждём, пока сервис поднимется.
      for _ in {1..15}; do
        if systemctl is-active --quiet portmaster.service; then
          echo "Portmaster запущен."
          exit 0
        fi
        sleep 1
      done

      echo "Portmaster не запустился за 15 секунд." >&2
      sudo systemctl status portmaster.service --no-pager || true
      exit 1
    '';
  };

  # --- Остановка ядра ---
  portmasterStop = pkgs.writeShellApplication {
    name = "portmaster-stop-core";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail

      STATUS=$(systemctl is-active portmaster.service 2>/dev/null || echo "inactive")
      if [ "$STATUS" != "active" ]; then
        echo "Portmaster не запущен."
        exit 0
      fi

      echo "Останавливаю Portmaster..."
      sudo systemctl stop portmaster.service
      echo "Готово."
    '';
  };

  # --- Перезапуск ядра ---
  portmasterRestart = pkgs.writeShellApplication {
    name = "portmaster-restart-core";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail

      echo "Перезапускаю Portmaster..."
      sudo systemctl restart portmaster.service

      for _ in {1..15}; do
        if systemctl is-active --quiet portmaster.service; then
          echo "Portmaster перезапущен."
          exit 0
        fi
        sleep 1
      done

      echo "Portmaster не поднялся за 15 секунд." >&2
      sudo systemctl status portmaster.service --no-pager || true
      exit 1
    '';
  };

  # --- Статус ---
  portmasterStatus = pkgs.writeShellApplication {
    name = "portmaster-status";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      STATUS=$(systemctl is-active portmaster.service 2>/dev/null || echo "unknown")
      echo "Состояние portmaster.service: $STATUS"

      case "$STATUS" in
        active)   echo "  → Ядро Portmaster работает." ;;
        inactive) echo "  → Ядро остановлено. Запустите: portmaster-start-core" ;;
        failed)   echo "  → Сервис упал. Смотрите логи: journalctl -u portmaster -n 50" ;;
      esac

      echo
      echo "Последние строки лога:"
      journalctl -u portmaster.service -n 5 --no-pager 2>/dev/null || true
    '';
  };

  # --- Ярлык для запуска через pkexec (запрос пароля в KDE-диалоге) ---
  portmasterStartGui = pkgs.writeShellScriptBin "portmaster-start-gui" ''
    exec ${pkgs.pkexec-kde}/bin/pkexec ${portmasterStart}/bin/portmaster-start-core
  '';

  portmasterStopGui = pkgs.writeShellScriptBin "portmaster-stop-gui" ''
    exec ${pkgs.pkexec-kde}/bin/pkexec ${portmasterStop}/bin/portmaster-stop-core
  '';

in
{
  # === Команды в PATH ===
  home.packages = [
    portmasterStart
    portmasterStop
    portmasterRestart
    portmasterStatus
    portmasterStartGui
    portmasterStopGui
  ];

  # === Ярлыки в меню приложений KDE ===
  xdg.desktopEntries = {
    portmaster-start = {
      name = "Portmaster Start";
      genericName = "Start Portmaster core";
      exec = "portmaster-start-gui";
      icon = "security-high";
      terminal = false;
      categories = [ "System" "Security" ];
    };
    portmaster-stop = {
      name = "Portmaster Stop";
      genericName = "Stop Portmaster core";
      exec = "portmaster-stop-gui";
      icon = "process-stop";
      terminal = false;
      categories = [ "System" "Security" ];
    };
  };
}
