{ config, pkgs, ... }:

let
  # =====================================================================
  # DeepSeek Harness (dsh) — сборка из исходников и запуск.
  #
  # Скрипты:
  #   dsh-install           — клонировать репозиторий, собрать
  #   dsh-start             — запустить веб-интерфейс
  #   dsh-stop              — остановить
  #   dsh-remove            — удалить репозиторий и данные
  #   dsh-check-update      — проверить обновления в upstream
  #   dsh-update            — обновить (с сохранением локальных конфигов)
  #
  # Конфигурация DSH хранится в ~/.dsh (DSH_HOME), не в репозитории.
  # При обновлении через git pull эти настройки не затрагиваются.
  # =====================================================================

  # --- Установка (одноразово) ---
  dshInstall = pkgs.writeShellApplication {
    name = "dsh-install";
    runtimeInputs = [ pkgs.git pkgs.nodejs_22 pkgs.pnpm pkgs.curl ];
    text = ''
      set -euo pipefail
      REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      DSH_HOME="''${HOME}/.dsh"

      if [ -d "$REPO_DIR" ]; then
        echo "Репозиторий '$REPO_DIR' уже существует."
        echo "Для переустановки сначала запустите dsh-remove."
        exit 1
      fi

      echo "Клонирую DeepSeek Harness..."
      mkdir -p "''${HOME}/llm"
      git clone "$REPO_URL" "$REPO_DIR"
      cd "$REPO_DIR"

      echo "Устанавливаю зависимости (pnpm install)..."
      pnpm install

      echo "Собираю (pnpm run build)..."
      pnpm run build

      echo
      echo "DeepSeek Harness установлен в $REPO_DIR"
      echo "Конфигурация будет храниться в $DSH_HOME"
      echo
      echo "Запуск: dsh-start"
      echo "Обновление: dsh-update"
      echo "Удаление: dsh-remove"
    '';
  };

  # --- Запуск ---
  dshStart = pkgs.writeShellApplication {
    name = "dsh-start";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.pnpm pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      PORT=3000
      URL="http://localhost:$PORT"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install" >&2
        exit 1
      fi

      cd "$REPO_DIR"

      echo "Запускаю DeepSeek Harness на порту $PORT..."
      # pnpm dsh web — запускает веб-сервер в фоне
      pnpm dsh web --port "$PORT" > /tmp/dsh.log 2>&1 &
      DSH_PID=$!
      echo "PID: $DSH_PID (лог: /tmp/dsh.log)"

      echo -n "Ожидание сервиса"
      for _ in {1..60}; do
        if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
          echo " — готов."
          break
        fi
        echo -n "."
        sleep 1
      done

      echo "Открываю $URL"
      xdg-open "$URL" &
    '';
  };

  # --- Остановка ---
  dshStop = pkgs.writeShellApplication {
    name = "dsh-stop";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      set -euo pipefail
      echo "Останавливаю процессы DeepSeek Harness..."
      pkill -f "pnpm dsh web" 2>/dev/null || true
      echo "Готово."
    '';
  };

  # --- Удаление ---
  dshRemove = pkgs.writeShellApplication {
    name = "dsh-remove";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      DSH_HOME="''${HOME}/.dsh"

      read -r -p "Удалить репозиторий '$REPO_DIR'? [y/N] " answer
      if [[ "''${answer,,}" == "y" ]]; then
        rm -rf "$REPO_DIR"
        echo "Репозиторий удалён."
      fi

      read -r -p "Удалить конфигурацию '$DSH_HOME' (настройки, сессии)? [y/N] " answer
      if [[ "''${answer,,}" == "y" ]]; then
        rm -rf "$DSH_HOME"
        echo "Конфигурация удалена."
      fi

      echo "Готово."
    '';
  };

  # --- Проверка обновлений ---
  dshCheckUpdate = pkgs.writeShellApplication {
    name = "dsh-check-update";
    runtimeInputs = [ pkgs.git ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install"
        exit 1
      fi

      cd "$REPO_DIR"
      echo "Проверяю обновления в upstream..."
      git fetch origin

      LOCAL=$(git rev-parse HEAD)
      REMOTE=$(git rev-parse origin/main)

      if [ "$LOCAL" = "$REMOTE" ]; then
        echo "Обновление не требуется — установлена последняя версия."
      else
        echo "Доступно обновление."
        echo "Локальная версия:  $LOCAL"
        echo "Удалённая версия:  $REMOTE"
        echo "Применить: dsh-update"
      fi
    '';
  };

  # --- Обновление с сохранением локальных изменений ---
  dshUpdate = pkgs.writeShellApplication {
    name = "dsh-update";
    runtimeInputs = [ pkgs.git pkgs.nodejs_22 pkgs.pnpm ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      DSH_HOME="''${HOME}/.dsh"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install"
        exit 1
      fi

      cd "$REPO_DIR"

      # Проверяем, есть ли локальные изменения (незакоммиченные).
      if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Обнаружены локальные изменения в репозитории."
        echo "Сохраняю их во временное хранилище (git stash)..."
        git stash push -m "dsh-update-$(date +%Y%m%d-%H%M%S)"
        STASHED=1
      else
        STASHED=0
      fi

      echo "Обновляю из upstream..."
      git pull --ff-only origin main

      echo "Устанавливаю обновлённые зависимости..."
      pnpm install

      echo "Пересобираю..."
      pnpm run build

      if [ "$STASHED" -eq 1 ]; then
        echo "Восстанавливаю локальные изменения..."
        if git stash pop; then
          echo "Локальные изменения восстановлены."
        else
          echo "ВНИМАНИЕ: конфликт при восстановлении. Проверьте git status вручную."
          echo "Ваши изменения сохранены в git stash. Посмотреть: git stash list"
        fi
      fi

      echo
      echo "Обновление завершено."
      echo "Конфигурация в $DSH_HOME не затронута."
      echo "Запуск: dsh-start"
    '';
  };

in
{
  home.packages = [
    dshInstall
    dshStart
    dshStop
    dshRemove
    dshCheckUpdate
    dshUpdate
  ];

  xdg.desktopEntries = {
    dsh-start = {
      name = "DeepSeek Harness Start";
      genericName = "Start DeepSeek Harness";
      exec = "dsh-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" ];
    };
    dsh-stop = {
      name = "DeepSeek Harness Stop";
      genericName = "Stop DeepSeek Harness";
      exec = "dsh-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" ];
    };
  };
}
