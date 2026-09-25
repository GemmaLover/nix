{ config, pkgs, ... }:

let
  # =====================================================================
  # DeepSeek Harness (dsh) — сборка из исходников, запуск веб-UI.
  #
  # Репозиторий: https://github.com/deepseek-ai/deepseek-harness
  # Монорепо на pnpm, Node.js ≥ 22.19, сборка через `pnpm run build`.
  # Запуск: `pnpm dsh web` — поднимает Web UI на 3080 внутри репозитория.
  #
  # Скрипты:
  #   dsh-install         — клонировать, собрать (одноразово)
  #   dsh-start           — запустить веб-UI на порту 3085
  #   dsh-stop            — остановить
  #   dsh-remove          — удалить репозиторий и конфиг (по выбору)
  #   dsh-check-update    — проверить обновления в upstream
  #   dsh-update          — обновить, сохранив локальные правки через git stash
  #
  # Конфиги DSH хранятся в ~/.dsh (переменная DSH_HOME) — вне репозитория,
  # при обновлении не затрагиваются. Правки в файлах репозитория (например,
  # cordis.yml) сохраняются через git stash.
  # =====================================================================

  # --- Общие переменные для всех скриптов (дублируются в каждом, чтобы
  #     shellcheck не ругался на неиспользуемые переменные). ---

  # --- Установка (одноразово) ---
  dshInstall = pkgs.writeShellApplication {
    name = "dsh-install";
    runtimeInputs = [ pkgs.git pkgs.nodejs_22 pkgs.pnpm ];
    text = ''
      set -euo pipefail
      REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
      REPO_DIR="''${HOME}/llm/deepseek-harness"

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
      echo "  Внимание: сборка может занять 5-15 минут."
      pnpm run build

      echo
      echo "DeepSeek Harness установлен в $REPO_DIR"
      echo "Конфигурация будет создана в ''${HOME}/.dsh при первом запуске."
      echo
      echo "Запуск:    dsh-start"
      echo "Обновление: dsh-update"
      echo "Удаление:  dsh-remove"
    '';
  };

  # --- Запуск ---
  dshStart = pkgs.writeShellApplication {
    name = "dsh-start";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.pnpm pkgs.curl pkgs.xdg-utils pkgs.procps ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      PORT=3085
      URL="http://localhost:$PORT"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install" >&2
        exit 1
      fi

      # Проверяем, не запущен ли уже.
      if pgrep -f "dsh web" >/dev/null 2>&1; then
        echo "DeepSeek Harness уже запущен."
        echo "Останавливаю предыдущий экземпляр, чтобы не было конфликта портов..."
        pkill -f "dsh web" 2>/dev/null || true
        sleep 2
      fi

      cd "$REPO_DIR"

      echo "Запускаю DeepSeek Harness на порту $PORT..."
      # --no-open: не пытаться открыть браузер самому — откроем позже.
      # --port: задаём порт явно.
      # Логи пишем в /tmp/dsh.log.
      nohup pnpm dsh web --no-open --port "$PORT" >/tmp/dsh.log 2>&1 &
      echo "PID: $!"
      echo "Лог: /tmp/dsh.log"

      echo -n "Ожидание сервиса"
      for _ in {1..90}; do
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
      if ! pgrep -f "dsh web" >/dev/null 2>&1; then
        echo "DeepSeek Harness не запущен — нечего останавливать."
        exit 0
      fi

      echo "Останавливаю DeepSeek Harness..."
      pkill -f "dsh web" 2>/dev/null || true
      sleep 1
      echo "Готово."
    '';
  };

  # --- Удаление ---
  dshRemove = pkgs.writeShellApplication {
    name = "dsh-remove";
    runtimeInputs = [ pkgs.coreutils pkgs.procps ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      DSH_HOME="''${HOME}/.dsh"

      # Останавливаем, если запущен.
      pkill -f "dsh web" 2>/dev/null || true

      if [ -d "$REPO_DIR" ]; then
        read -r -p "Удалить репозиторий '$REPO_DIR' (≈200 МБ)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          rm -rf "$REPO_DIR"
          echo "Репозиторий удалён."
        else
          echo "Репозиторий сохранён."
        fi
      else
        echo "Репозиторий '$REPO_DIR' не найден."
      fi

      if [ -d "$DSH_HOME" ]; then
        read -r -p "Удалить конфигурацию '$DSH_HOME' (настройки, сессии, креды)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          rm -rf "$DSH_HOME"
          echo "Конфигурация удалена."
        else
          echo "Конфигурация сохранена."
        fi
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

      # Определяем основную ветку (main или master).
      BRANCH=$(git rev-parse --abbrev-ref HEAD)
      LOCAL=$(git rev-parse HEAD)
      REMOTE=$(git rev-parse "origin/$BRANCH")

      echo "Ветка: $BRANCH"
      echo "Локально:  $LOCAL"
      echo "В upstream: $REMOTE"
      echo

      if [ "$LOCAL" = "$REMOTE" ]; then
        echo "Обновление не требуется — установлена последняя версия."
      else
        echo "Доступно обновление."
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

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install"
        exit 1
      fi

      cd "$REPO_DIR"
      BRANCH=$(git rev-parse --abbrev-ref HEAD)

      # Проверяем, есть ли локальные изменения (незакоммиченные).
      if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Обнаружены локальные изменения в репозитории."
        echo "Сохраняю их во временное хранилище (git stash)..."
        STASH_NAME="dsh-update-$(date +%Y%m%d-%H%M%S)"
        git stash push -m "$STASH_NAME"
        STASHED=1
      else
        STASHED=0
      fi

      echo "Обновляю из upstream (ветка $BRANCH)..."
      git pull --ff-only origin "$BRANCH"

      echo "Устанавливаю обновлённые зависимости (pnpm install)..."
      pnpm install

      echo "Пересобираю (pnpm run build)..."
      echo "  Внимание: сборка может занять 5-15 минут."
      pnpm run build

      if [ "$STASHED" -eq 1 ]; then
        echo "Восстанавливаю локальные изменения..."
        if git stash pop; then
          echo "Локальные изменения восстановлены."
        else
          echo "ВНИМАНИЕ: конфликт при восстановлении."
          echo "Ваши изменения сохранены в git stash."
          echo "Посмотреть: cd $REPO_DIR && git stash list"
          echo "Разрешить вручную и удалить stash после."
        fi
      fi

      echo
      echo "Обновление завершено."
      echo "Конфигурация в ''${HOME}/.dsh не затронута."
      echo "Запуск: dsh-start"
    '';
  };

in
{
  # === Пользовательские команды ===
  home.packages = [
    dshInstall
    dshStart
    dshStop
    dshRemove
    dshCheckUpdate
    dshUpdate
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    dsh-start = {
      name = "DeepSeek Harness Start";
      genericName = "Start DeepSeek Harness web UI";
      exec = "dsh-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    dsh-stop = {
      name = "DeepSeek Harness Stop";
      genericName = "Stop DeepSeek Harness";
      exec = "dsh-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
