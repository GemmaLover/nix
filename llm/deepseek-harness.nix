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
  #   dsh-install         — клонировать или обновить, пересобрать (идемпотентно)
  #   dsh-rebuild         — пересобрать без git-обновления
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

  # Официальный Node.js с nodejs.org — для совместимости с нативным аддоном
  # node-addon-require-builtin, который не работает с Nix-сборкой Node.js.
  nodejs-official = pkgs.callPackage ../pkgs/nodejs-official { };

  # --- Установка / переустановка (идемпотентно) ---
  dshInstall = pkgs.writeShellApplication {
    name = "dsh-install";
    runtimeInputs = [
      pkgs.git
      nodejs-official
      pkgs.pnpm
      # Инструменты для сборки нативных модулей Node.js (node-gyp).
      # Без них node-gyp не может найти компилятор C (cc).
      pkgs.gcc
      pkgs.gnumake
      pkgs.python3
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail
      REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
      REPO_DIR="''${HOME}/llm/deepseek-harness"

      # --- Клонирование или обновление исходников ---
      if [ ! -d "$REPO_DIR" ]; then
        echo "Клонирую DeepSeek Harness..."
        mkdir -p "''${HOME}/llm"
        git clone "$REPO_URL" "$REPO_DIR"
      else
        echo "Репозиторий уже есть — обновляю исходники без удаления."
        cd "$REPO_DIR"
        git fetch origin
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        git reset --hard "origin/$BRANCH"
      fi

      cd "$REPO_DIR"

      # --- Сброс скомпилированных артефактов ---
      # Нативные модули в node_modules собраны против конкретного Node.js ABI.
      # После смены Node.js (например, на официальный) их нужно пересобрать.
      echo "Удаляю node_modules и build-артефакты..."
      rm -rf node_modules
      rm -rf apps/*/node_modules
      rm -rf packages/*/*/node_modules
      rm -rf vendor/*/node_modules
      # Кэш pnpm — не удаляем, чтобы не тянуть всё заново.
      # Build-выходы: lib/ и dist/ в каждом пакете (кроме node_modules).
      find apps packages vendor -maxdepth 4 -type d \( -name lib -o -name dist \) \
        -path '*/node_modules' -prune -o -type d \( -name lib -o -name dist \) -print0 2>/dev/null \
        | xargs -0 rm -rf 2>/dev/null || true

      # --- Установка зависимостей и сборка ---
      echo "Устанавливаю зависимости (pnpm install)..."
      pnpm install

      echo "Собираю (pnpm run build)..."
      echo "  Внимание: сборка может занять 5-15 минут."
      pnpm run build

      echo
      echo "DeepSeek Harness установлен в $REPO_DIR"
      echo "Конфигурация будет создана в ''${HOME}/.dsh при первом запуске."
      echo
      echo "Запуск:      dsh-start"
      echo "Пересборка:  dsh-rebuild (без git)"
      echo "Обновление:  dsh-update (с git pull)"
      echo "Удаление:    dsh-remove"
    '';
  };

  # --- Пересборка без обновления исходников ---
  dshRebuild = pkgs.writeShellApplication {
    name = "dsh-rebuild";
    runtimeInputs = [
      nodejs-official
      pkgs.pnpm
      pkgs.gcc
      pkgs.gnumake
      pkgs.python3
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install" >&2
        exit 1
      fi

      cd "$REPO_DIR"

      echo "Удаляю node_modules и build-артефакты..."
      rm -rf node_modules
      rm -rf apps/*/node_modules packages/*/*/node_modules vendor/*/node_modules
      find apps packages vendor -maxdepth 4 -type d \( -name lib -o -name dist \) \
        -path '*/node_modules' -prune -o -type d \( -name lib -o -name dist \) -print0 2>/dev/null \
        | xargs -0 rm -rf 2>/dev/null || true

      echo "Устанавливаю зависимости (pnpm install)..."
      pnpm install

      echo "Собираю (pnpm run build)..."
      pnpm run build

      echo
      echo "Пересборка завершена."
    '';
  };

  # --- Запуск ---
  # --- Запуск ---
  dshStart = pkgs.writeShellApplication {
    name = "dsh-start";
    runtimeInputs = [
      nodejs-official
      pkgs.pnpm
      pkgs.curl
      pkgs.xdg-utils
      pkgs.procps
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail
      REPO_DIR="''${HOME}/llm/deepseek-harness"
      LOG_FILE="/tmp/dsh.log"

      if [ ! -d "$REPO_DIR" ]; then
        echo "Репозиторий не найден. Сначала запустите dsh-install" >&2
        exit 1
      fi

      # Если уже запущен — останавливаем.
      if pgrep -f "dsh web" >/dev/null 2>&1; then
        echo "DeepSeek Harness уже запущен. Перезапускаю..."
        pkill -f "dsh web" 2>/dev/null || true
        sleep 2
      fi

      cd "$REPO_DIR"

      # Очищаем старый лог, чтобы URL из прошлого запуска не сбивал с толку.
      : > "$LOG_FILE"

      echo "Запускаю DeepSeek Harness..."
      # Запускаем через официальный Node.js с --expose-internals.
      # --no-open — CLI не открывает браузер сам, URL печатает в stdout.
      # Порт CLI выбирает сам (обычно 3080).
      nohup ${nodejs-official}/bin/node --expose-internals \
        apps/cli/lib/bin.js web --no-open \
        >"$LOG_FILE" 2>&1 &
      echo "PID: $!"
      echo "Лог: $LOG_FILE"

      # Ждём появления URL в логе (макс. 90 секунд).
      echo -n "Ожидание URL в логе"
      URL=""
      for _ in {1..90}; do
        URL=$(grep -oE 'http://[0-9.]+:[0-9]+/\?token=[A-Za-z0-9_-]+' "$LOG_FILE" | head -1 || true)
        if [ -n "$URL" ]; then
          echo " — найден."
          break
        fi
        echo -n "."
        sleep 1
      done

      if [ -z "$URL" ]; then
        echo " — не дождались URL за 90 секунд."
        echo "Проверьте лог вручную: cat $LOG_FILE"
        exit 1
      fi

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
    runtimeInputs = [
      pkgs.git
      nodejs-official
      pkgs.pnpm
      pkgs.gcc
      pkgs.gnumake
      pkgs.python3
      pkgs.findutils
    ];
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

      echo "Удаляю node_modules и build-артефакты..."
      rm -rf node_modules
      rm -rf apps/*/node_modules packages/*/*/node_modules vendor/*/node_modules
      find apps packages vendor -maxdepth 4 -type d \( -name lib -o -name dist \) \
        -path '*/node_modules' -prune -o -type d \( -name lib -o -name dist \) -print0 2>/dev/null \
        | xargs -0 rm -rf 2>/dev/null || true

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
    dshRebuild
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
