# Команды для локального DSH (порт 7718).
#
# Установка:   dsh-local-install        — клонирует/обновляет репо, собирает
# Пересборка:  dsh-local-rebuild        — rebuild без git pull
# Запуск:      dsh-local-start          — стартует web-UI, открывает браузер
# Остановка:   dsh-local-stop           — убивает процесс
# Обновление:  dsh-local-update         — git pull + rebuild (с git stash)
# Проверка:    dsh-local-check-update   — проверить обновления в upstream
# Удаление:    dsh-local-remove         — удаляет репо и/или конфиг ~/.dsh
#
# Конфиг DSH хранится в ~/.dsh (DSH_HOME) — вне репозитория, при
# обновлении не затрагивается.
#
# ВАЖНО: `npm_config_manage_package_manager_versions=false` обязателен.
# В package.json DSH прописан `packageManager: "pnpm@<X.Y.Z>"`. Без этой
# переменной Nix-версия pnpm пытается скачать и запустить другую версию
# pnpm в ~/.local/share/pnpm/package-manager-store/, а та — динамически
# слинкованный бинарник, который NixOS запускать не умеет:
#   "Could not start dynamically linked executable: .../pnpm"
# Переменная говорит pnpm игнорировать `packageManager` и использовать
# собственную версию из /nix/store.
{ config, pkgs, lib, dshLocalConfig, ... }:

let
  inherit (dshLocalConfig) port repoDir repoUrl nodejs pnpm;

  # Общие runtimeInputs для install/update/rebuild.
  buildInputs = [
    pkgs.git
    nodejs
    pnpm
    pkgs.gcc
    pkgs.gnumake
    pkgs.python3
    pkgs.findutils
  ];
in
{
  # === Установка / переустановка (идемпотентно) ===
  home.packages = [
    (pkgs.writeShellApplication {
      name = "dsh-local-install";
      runtimeInputs = buildInputs;
      text = ''
        set -euo pipefail

        # Отключаем самоуправление версиями pnpm. См. комментарий в шапке файла.
        export npm_config_manage_package_manager_versions=false

        REPO_URL="${repoUrl}"
        REPO_DIR="${repoDir}"

        if [ ! -d "$REPO_DIR" ]; then
          echo "Клонирую DeepSeek Harness в $REPO_DIR..."
          mkdir -p "$(dirname "$REPO_DIR")"
          git clone "$REPO_URL" "$REPO_DIR"
        else
          echo "Репозиторий уже есть — обновляю исходники."
          cd "$REPO_DIR"
          git fetch origin
          BRANCH=$(git rev-parse --abbrev-ref HEAD)
          git reset --hard "origin/$BRANCH"
        fi

        cd "$REPO_DIR"

        echo "Удаляю node_modules и build-артефакты..."
        rm -rf node_modules
        rm -rf apps/*/node_modules
        rm -rf packages/*/*/node_modules
        rm -rf vendor/*/node_modules
        find apps packages vendor -maxdepth 4 -type d \( -name lib -o -name dist \) \
          -path '*/node_modules' -prune -o -type d \( -name lib -o -name dist \) -print0 2>/dev/null \
          | xargs -0 rm -rf 2>/dev/null || true

        echo "Устанавливаю зависимости (pnpm install)..."
        pnpm install

        echo "Собираю (pnpm run build)..."
        echo "  Внимание: сборка может занять 5-15 минут."
        pnpm run build

        echo
        echo "DeepSeek Harness установлен в $REPO_DIR"
        echo "Конфигурация будет создана в ''${HOME}/.dsh при первом запуске."
        echo
        echo "Запуск:      dsh-local-start"
        echo "Пересборка:  dsh-local-rebuild"
        echo "Обновление:  dsh-local-update"
        echo "Удаление:    dsh-local-remove"
      '';
    })

    # === Пересборка без git pull ===
    (pkgs.writeShellApplication {
      name = "dsh-local-rebuild";
      runtimeInputs = buildInputs;
      text = ''
        set -euo pipefail
        export npm_config_manage_package_manager_versions=false

        REPO_DIR="${repoDir}"

        if [ ! -d "$REPO_DIR" ]; then
          echo "Репозиторий не найден. Сначала: dsh-local-install" >&2
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
    })

    # === Запуск ===
    (pkgs.writeShellApplication {
      name = "dsh-local-start";
      runtimeInputs = [
        nodejs
        pnpm
        pkgs.curl
        pkgs.xdg-utils
        pkgs.procps
        pkgs.gnugrep
      ];
      text = ''
        set -euo pipefail
        export npm_config_manage_package_manager_versions=false

        REPO_DIR="${repoDir}"
        PORT=${toString port}
        LOG_FILE="/tmp/dsh-local.log"
        PROC_PATTERN="apps/cli/lib/bin.js web"
        ENTRY="${repoDir}/apps/cli/lib/bin.js"

        if [ ! -d "$REPO_DIR" ]; then
          echo "Репозиторий не найден. Сначала: dsh-local-install" >&2
          exit 1
        fi

        # Проверяем, что сборка выполнена. Если нет — подсказываем.
        if [ ! -f "$ENTRY" ]; then
          echo "Не найден собранный бинарник: $ENTRY" >&2
          echo "Похоже, сборка не выполнялась или упала." >&2
          echo "Запустите: dsh-local-install" >&2
          exit 1
        fi

        if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
          echo "DSH уже запущен. Перезапускаю..."
          pkill -f "$PROC_PATTERN" 2>/dev/null || true
          sleep 2
        fi

        cd "$REPO_DIR"
        : > "$LOG_FILE"

        echo "Запускаю DeepSeek Harness на порту $PORT..."
        # --port задаёт порт web-интерфейса (по умолчанию 3080).
        # --no-open — CLI не открывает браузер сам, мы сделаем это ниже.
        nohup ${nodejs}/bin/node --expose-internals \
          apps/cli/lib/bin.js web --port "$PORT" --no-open \
          >"$LOG_FILE" 2>&1 &
        echo "PID: $!"
        echo "Лог: $LOG_FILE"

        echo -n "Ожидание URL в логе"
        URL=""
        for _ in {1..90}; do
          URL=$(grep -oE "http://[0-9.]+:$PORT/\\?token=[A-Za-z0-9_-]+" "$LOG_FILE" | head -1 || true)
          if [ -n "$URL" ]; then
            echo " — найден."
            break
          fi
          echo -n "."
          sleep 1
        done

        if [ -z "$URL" ]; then
          echo " — не дождались URL за 90 секунд."
          echo "Проверьте лог: cat $LOG_FILE"
          exit 1
        fi

        echo "Открываю $URL"
        xdg-open "$URL" &
      '';
    })

    # === Остановка ===
    (pkgs.writeShellApplication {
      name = "dsh-local-stop";
      runtimeInputs = [ pkgs.procps ];
      text = ''
        set -euo pipefail
        PROC_PATTERN="apps/cli/lib/bin.js web"

        if ! pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
          echo "DSH не запущен."
          exit 0
        fi

        echo "Останавливаю DSH..."
        pkill -f "$PROC_PATTERN" 2>/dev/null || true
        sleep 1
        echo "Готово."
      '';
    })

    # === Проверка обновлений ===
    (pkgs.writeShellApplication {
      name = "dsh-local-check-update";
      runtimeInputs = [ pkgs.git ];
      text = ''
        set -euo pipefail
        REPO_DIR="${repoDir}"

        if [ ! -d "$REPO_DIR" ]; then
          echo "Репозиторий не найден. Сначала: dsh-local-install"
          exit 1
        fi

        cd "$REPO_DIR"
        git fetch origin
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$BRANCH")

        echo "Ветка: $BRANCH"
        echo "Локально:  $LOCAL"
        echo "В upstream: $REMOTE"

        if [ "$LOCAL" = "$REMOTE" ]; then
          echo "Обновление не требуется."
        else
          echo "Доступно обновление. Применить: dsh-local-update"
        fi
      '';
    })

    # === Обновление с сохранением локальных правок ===
    (pkgs.writeShellApplication {
      name = "dsh-local-update";
      runtimeInputs = buildInputs;
      text = ''
        set -euo pipefail
        export npm_config_manage_package_manager_versions=false

        REPO_DIR="${repoDir}"

        if [ ! -d "$REPO_DIR" ]; then
          echo "Репозиторий не найден. Сначала: dsh-local-install"
          exit 1
        fi

        cd "$REPO_DIR"
        BRANCH=$(git rev-parse --abbrev-ref HEAD)

        if ! git diff --quiet || ! git diff --cached --quiet; then
          echo "Сохраняю локальные изменения в git stash..."
          STASH_NAME="dsh-update-$(date +%Y%m%d-%H%M%S)"
          git stash push -m "$STASH_NAME"
          STASHED=1
        else
          STASHED=0
        fi

        git pull --ff-only origin "$BRANCH"

        echo "Удаляю node_modules и build-артефакты..."
        rm -rf node_modules
        rm -rf apps/*/node_modules packages/*/*/node_modules vendor/*/node_modules
        find apps packages vendor -maxdepth 4 -type d \( -name lib -o -name dist \) \
          -path '*/node_modules' -prune -o -type d \( -name lib -o -name dist \) -print0 2>/dev/null \
          | xargs -0 rm -rf 2>/dev/null || true

        pnpm install
        pnpm run build

        if [ "$STASHED" -eq 1 ]; then
          if git stash pop; then
            echo "Локальные изменения восстановлены."
          else
            echo "ВНИМАНИЕ: конфликт. Изменения в git stash."
          fi
        fi

        echo "Обновление завершено. Конфиг ~/.dsh не затронут."
      '';
    })

    # === Удаление ===
    (pkgs.writeShellApplication {
      name = "dsh-local-remove";
      runtimeInputs = [ pkgs.coreutils pkgs.procps ];
      text = ''
        set -euo pipefail
        REPO_DIR="${repoDir}"
        DSH_HOME="''${HOME}/.dsh"
        PROC_PATTERN="apps/cli/lib/bin.js web"

        pkill -f "$PROC_PATTERN" 2>/dev/null || true

        if [ -d "$REPO_DIR" ]; then
          read -r -p "Удалить репозиторий '$REPO_DIR' (≈200 МБ)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$REPO_DIR"
            echo "Репозиторий удалён."
          else
            echo "Репозиторий сохранён."
          fi
        fi

        if [ -d "$DSH_HOME" ]; then
          read -r -p "Удалить конфигурацию '$DSH_HOME'? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$DSH_HOME"
            echo "Конфигурация удалена."
          fi
        fi
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    dsh-local-start = {
      name = "DSH (local) Start";
      exec = "dsh-local-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    dsh-local-stop = {
      name = "DSH (local) Stop";
      exec = "dsh-local-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
