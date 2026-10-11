{ config, pkgs, lib, gufoConfig, ... }:

let
  inherit (gufoConfig) image portHost portContainer gufoDir modelsDir repoUrl;
in
{
  home.packages = [
    # =====================================================================
    # Одноразовая установка Gufo. ИНТЕРАКТИВНАЯ.
    #
    # Как у strata:
    #   1. git clone на хосте → ~/llm/gufo
    #   2. podman run --rm -it с монтированием ~/llm/gufo → /opt/gufo
    #   3. Внутри: смена зеркал Fedora → dnf5 install → ./setup.sh
    #
    # Если в репо Gufo нет setup.sh — команда скажет об этом, и вы
    # сможете поправить entrypoint (или подскажете мне README — подгоню).
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "gufo-setup";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        GUFO_DIR="${gufoDir}"
        MODELS_DIR="${modelsDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}
        PIP_CACHE_DIR="$GUFO_DIR/.pip-cache"

        mkdir -p "$GUFO_DIR" "$MODELS_DIR" "$PIP_CACHE_DIR"

        # === Шаг 1: клонируем/обновляем Gufo НА ХОСТЕ ===
        if [ ! -d "$GUFO_DIR/.git" ]; then
          echo "Клонирую Gufo в $GUFO_DIR..."
          git clone "${repoUrl}" "$GUFO_DIR"
        else
          echo "Обновляю Gufo (git pull)..."
          git -C "$GUFO_DIR" pull --ff-only || echo "  (git pull пропущен)"
        fi

        if [ ! -x "$GUFO_DIR/setup.sh" ]; then
          echo "ОШИБКА: в $GUFO_DIR нет setup.sh" >&2
          echo "Проверьте содержимое: ls $GUFO_DIR" >&2
          echo "Если установка идёт иначе — правьте этот скрипт или пришлите README." >&2
          exit 1
        fi

        if ! podman image exists "$IMAGE" 2>/dev/null; then
          echo "Образ '$IMAGE' отсутствует. Скачиваю..."
          podman pull "$IMAGE"
        fi

        if [ -d "$PIP_CACHE_DIR" ]; then
          CACHE_SIZE=$(du -sh "$PIP_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
          echo "Кэш pip: $CACHE_SIZE (сохраняется между запусками)"
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка Gufo (интерактивная)."
        echo
        echo "  Репозиторий: $GUFO_DIR"
        echo "  Модели:      $MODELS_DIR"
        echo "  pip-кэш:     $PIP_CACHE_DIR (резюмирует обрывы)"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -p "$PORT_HOST:$PORT_CONTAINER" \
          -v "$GUFO_DIR:/opt/gufo:Z" \
          -v "$MODELS_DIR:/models:ro,Z" \
          -v "$PIP_CACHE_DIR:/root/.cache/pip:Z" \
          -e PIP_CACHE_DIR=/root/.cache/pip \
          -e PIP_RETRIES=30 \
          -e PIP_TIMEOUT=120 \
          -e PIP_DEFAULT_TIMEOUT=120 \
          -e PIP_RESUME_RETRIES=30 \
          -e PIP_PROGRESS_BAR=on \
          --entrypoint /bin/bash \
          "$IMAGE" \
          -c '
            set -e

            # === Шаг A: смена зеркал Fedora ===
            # ftp.fau.de использует /fedora/linux/... (проверено 200 OK).
            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora.repo \
                        /etc/yum.repos.d/fedora-updates.repo \
                        /etc/yum.repos.d/fedora-updates-archive.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
            done

            echo "=== Отключаю fedora-cisco-openh264 ==="
            for repo in /etc/yum.repos.d/fedora-cisco-openh264.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            echo "=== Отключаю AMD ROCm-репозиторий ==="
            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            # === Шаг B: установка инструментов сборки ===
            if command -v dnf5 >/dev/null 2>&1; then
              echo "=== Установка gcc-c++, make, git, cmake, ninja ==="
              dnf5 install -y --setopt=install_weak_deps=False \
                gcc-c++ make git cmake ninja-build
            elif command -v microdnf >/dev/null 2>&1; then
              microdnf install -y --setopt=install_weak_deps=0 \
                gcc-c++ make git cmake ninja-build
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y --setopt=install_weak_deps=False \
                gcc-c++ make git cmake ninja-build
            fi

            # === Шаг C: setup.sh ===
            # Если в репо Gufo setup.sh принимает аргументы (например,
            # путь к моделям или бэкенд) — добавьте их здесь.
            cd /opt/gufo && ./setup.sh
          '

        echo
        echo "Установка завершена."
        echo "Репозиторий: $GUFO_DIR"
        echo "Модели:      $MODELS_DIR"
        echo "Запуск: gufo-start"
      '';
    })

    # =====================================================================
    # Запуск сервера Gufo. Требует, чтобы setup уже был выполнен.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "gufo-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="gufo-server"
        IMAGE="${image}"
        GUFO_DIR="${gufoDir}"
        MODELS_DIR="${modelsDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        if [ ! -d "$GUFO_DIR/.git" ]; then
          echo "Gufo не установлен в $GUFO_DIR" >&2
          echo "Сначала: gufo-setup" >&2
          exit 1
        fi

        if ! ls "$MODELS_DIR"/*.gguf >/dev/null 2>&1; then
          echo "ПРЕДУПРЕЖДЕНИЕ: в $MODELS_DIR нет .gguf-файлов." >&2
          echo "Скачайте модель, например:" >&2
          echo "  huggingface-cli download <repo> <file>.gguf --local-dir $MODELS_DIR" >&2
          echo
          read -r -p "Продолжить? [y/N] " answer
          [[ "''${answer,,}" == "y" ]] || exit 1
        fi

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Создаю сервисный контейнер..."
          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$GUFO_DIR:/opt/gufo:Z" \
            -v "$MODELS_DIR:/models:ro,Z" \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c "cd /opt/gufo && exec ./start.sh --host 0.0.0.0 --port ${toString portContainer}"
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$STATUS" = "running" ]; then
          echo "Контейнер '$CONTAINER_NAME' уже запущен."
        else
          echo "Запускаю сервер (статус был: $STATUS)..."
          podman start "$CONTAINER_NAME"
        fi

        URL="http://localhost:$PORT_HOST"
        echo -n "Ожидание сервиса"
        for _ in {1..300}; do
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
    })

    # === Остановка ===
    (pkgs.writeShellApplication {
      name = "gufo-stop";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="gufo-server"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Сервисный контейнер не найден."
          exit 0
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю..."
            podman stop -t 60 "$CONTAINER_NAME" 2>/dev/null || {
              echo "SIGTERM не сработал, kill..."
              podman kill "$CONTAINER_NAME" 2>/dev/null || true
            }
            ;;
          *)
            echo "Уже остановлен (статус: $STATUS)."
            ;;
        esac
        echo "Готово."
      '';
    })

    # === Удаление ===
    (pkgs.writeShellApplication {
      name = "gufo-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="gufo-server"
        IMAGE="${image}"
        GUFO_DIR="${gufoDir}"
        MODELS_DIR="${modelsDir}"

        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ '$IMAGE'? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            podman rmi "$IMAGE"
            echo "Образ удалён."
          else
            echo "Образ сохранён."
          fi
        fi

        if [ -d "$GUFO_DIR" ]; then
          SIZE=$(du -sh "$GUFO_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $GUFO_DIR ($SIZE — репозиторий + движок + pip-кэш)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$GUFO_DIR"
            echo "Репозиторий удалён."
          else
            echo "Репозиторий сохранён."
          fi
        fi

        if [ -d "$MODELS_DIR" ]; then
          SIZE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $MODELS_DIR ($SIZE — модели)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$MODELS_DIR"
            echo "Модели удалены."
          else
            echo "Модели сохранены."
          fi
        fi
        echo "Готово."
      '';
    })

    # === Обновление ===
    (pkgs.writeShellApplication {
      name = "gufo-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        GUFO_DIR="${gufoDir}"
        MODELS_DIR="${modelsDir}"
        PIP_CACHE_DIR="$GUFO_DIR/.pip-cache"

        if [ ! -d "$GUFO_DIR/.git" ]; then
          echo "Gufo не установлен. Сначала: gufo-setup" >&2
          exit 1
        fi

        mkdir -p "$PIP_CACHE_DIR"

        echo "Обновляю исходники (git pull на хосте)..."
        git -C "$GUFO_DIR" pull --ff-only

        echo
        echo "Пересборка (setup.sh в контейнере)..."
        echo

        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -v "$GUFO_DIR:/opt/gufo:Z" \
          -v "$MODELS_DIR:/models:ro,Z" \
          -v "$PIP_CACHE_DIR:/root/.cache/pip:Z" \
          -e PIP_CACHE_DIR=/root/.cache/pip \
          -e PIP_RETRIES=30 \
          -e PIP_TIMEOUT=120 \
          -e PIP_DEFAULT_TIMEOUT=120 \
          -e PIP_RESUME_RETRIES=30 \
          -e PIP_PROGRESS_BAR=on \
          --entrypoint /bin/bash \
          "$IMAGE" \
          -c '
            set -e

            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora.repo \
                        /etc/yum.repos.d/fedora-updates.repo \
                        /etc/yum.repos.d/fedora-updates-archive.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
            done

            for repo in /etc/yum.repos.d/fedora-cisco-openh264.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            if command -v dnf5 >/dev/null 2>&1; then
              dnf5 install -y --setopt=install_weak_deps=False \
                gcc-c++ make git cmake ninja-build
            elif command -v microdnf >/dev/null 2>&1; then
              microdnf install -y --setopt=install_weak_deps=0 \
                gcc-c++ make git cmake ninja-build
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y --setopt=install_weak_deps=False \
                gcc-c++ make git cmake ninja-build
            fi

            cd /opt/gufo && ./setup.sh
          '

        echo
        echo "Обновление завершено. Перезапустите сервер:"
        echo "  gufo-stop && gufo-start"
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    gufo-setup = {
      name = "Gufo Setup (first time)";
      exec = "gufo-setup";
      icon = "system-software-install";
      terminal = true;
      categories = [ "Development" "Science" ];
    };
    gufo-start = {
      name = "Gufo Start (port ${toString portHost})";
      exec = "gufo-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    gufo-stop = {
      name = "Gufo Stop";
      exec = "gufo-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
