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
  # ядра без ручного ввода systemctl, а также ярлыки в меню KDE.
  #
  # ВАЖНО: portmaster.service — системный юнит. Чтобы пользователь
  # lexi мог им управлять без пароля, ниже добавлено polkit-правило
  # (security.polkit.extraConfig). Поэтому в скриптах НЕТ ни sudo,
  # ни pkexec — systemctl вызывается напрямую.
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
      systemctl start portmaster.service

      # Ждём, пока сервис поднимется.
      for _ in {1..15}; do
        if systemctl is-active --quiet portmaster.service; then
          echo "Portmaster запущен."
          exit 0
        fi
        sleep 1
      done

      echo "Portmaster не запустился за 15 секунд." >&2
      systemctl status portmaster.service --no-pager || true
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
      systemctl stop portmaster.service
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
      systemctl restart portmaster.service

      for _ in {1..15}; do
        if systemctl is-active --quiet portmaster.service; then
          echo "Portmaster перезапущен."
          exit 0
        fi
        sleep 1
      done

      echo "Portmaster не поднялся за 15 секунд." >&2
      systemctl status portmaster.service --no-pager || true
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

in
{
  # === Команды в PATH ===
  # Все команды вызывают systemctl напрямую, без sudo и pkexec.
  # Polkit-правило ниже разрешает lexi управлять portmaster.service
  # без запроса пароля.
  home.packages = [
    portmasterStart
    portmasterStop
    portmasterRestart
    portmasterStatus
  ];

  # =====================================================================
  # Polkit-правило: разрешить пользователю lexi управлять
  # systemd-юнитом portmaster.service без ввода пароля.
  #
  # Без этого systemctl start/stop из ярлыков KDE требовал бы
  # root-пароль и не работал бы в графической сессии.
  # =====================================================================
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "portmaster.service" &&
          subject.user == "lexi") {
        return polkit.Result.YES;
      }
    });
  '';

  # === Ярлыки в меню приложений KDE ===
  # terminal = true — при запуске откроется окно терминала,
  # чтобы видеть вывод команд и любые ошибки.
  xdg.desktopEntries = {
    portmaster-start = {
      name = "Portmaster Start";
      genericName = "Start Portmaster core";
      exec = "portmaster-start-core";
      icon = "security-high";
      terminal = true;
      categories = [ "System" "Security" ];
    };
    portmaster-stop = {
      name = "Portmaster Stop";
      genericName = "Stop Portmaster core";
      exec = "portmaster-stop-core";
      icon = "process-stop";
      terminal = true;
      categories = [ "System" "Security" ];
    };
    portmaster-status = {
      name = "Portmaster Status";
      genericName = "Show Portmaster core status";
      exec = "portmaster-status";
      icon = "dialog-information";
      terminal = true;
      categories = [ "System" "Security" ];
    };
  };
}
