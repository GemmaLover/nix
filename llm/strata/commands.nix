{ config, pkgs, lib, strataConfig, ... }:

let
  inherit (strataConfig) image portHost portContainer strataDir;
in
{
  home.packages = [
    # =====================================================================
    # Одноразовая установка Strata. ИНТЕРАКТИВНАЯ.
    #
    # ПОДВОДНЫЕ КАМНИ ОБРАЗА kyuz0/amd-strix-halo-toolboxes:
    #   1. В образе НЕТ git — репозиторий клонируется НА ХОСТЕ.
    #   2. В образе НЕТ инструментов сборки (gcc-c++, make) — ставятся
    #      через dnf5 внутри контейнера перед setup.sh.
    #   3. Fedora-репозитории и AMD ROCm-репозиторий недоступны из РФ.
    #      Переключаем на ftp.fau.de, отключаем ROCm и cisco-openh264.
    #
    # ВАЖНО про ftp.fau.de: путь отличается от стандартного —
    #   https://ftp.fau.de/fedora/linux/releases/44/...   (а не /fedora/releases/44)
    #   https://ftp.fau.de/fedora/linux/updates/44/...    (а не /fedora/updates/44)
    # Поэтому в baseurl добавляется сегмент /linux.
    # Проверено вручную curl-ом: оба URL возвращают 200.
    #
    # Порядок:
    #   1. git clone на хосте → ~/llm/strata
    #   2. podman run --rm -it с монтированием ~/llm/strata → /opt/Strata
    #   3. Внутри: смена зеркал → dnf5 install → ./setup.sh
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        mkdir -p "$STRATA_DIR"

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Клонирую Strata в $STRATA_DIR..."
          git clone https://github.com/Niko1221/Strata.git "$STRATA_DIR"
        else
          echo "Обновляю Strata (git pull)..."
          git -C "$STRATA_DIR" pull --ff-only || echo "  (git pull пропущен)"
        fi

        if [ ! -x "$STRATA_DIR/setup.sh" ]; then
          echo "ОШИБКА: в $STRATA_DIR нет setup.sh" >&2
          exit 1
        fi

        if ! podman image exists "$IMAGE" 2>/dev/null; then
          echo "Образ '$IMAGE' отсутствует. Скачиваю..."
          podman pull "$IMAGE"
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка Strata (интерактивная)."
        echo
        echo "  Исходники, движок и модели будут в: $STRATA_DIR"
        echo "  Когда setup.sh спросит путь для моделей — укажи:"
        echo "    /opt/Strata/models"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -p "$PORT_HOST:$PORT_CONTAINER" \
          -v "$STRATA_DIR:/opt/Strata:Z" \
          --entrypoint /bin/bash \
          "$IMAGE" \
          -c '
            set -e

            # === Шаг A: смена зеркал Fedora ===
            # ftp.fau.de использует путь /fedora/linux/... (в отличие от
            # стандартного /fedora/...), поэтому добавляем /linux в baseurl.
            # Проверено: ftp.fau.de/fedora/linux/releases/44/... = 200,
            # ftp.fau.de/fedora/releases/44/... = 404.
            # Обрабатываем только реальные Fedora-репы с паттерном
            # download.example в baseurl. cisco-openh264 имеет другую
            # структуру — его отдельно отключаем ниже.
            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora.repo \
                        /etc/yum.repos.d/fedora-updates.repo \
                        /etc/yum.repos.d/fedora-updates-archive.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
            done

            # Отключаем fedora-cisco-openh264 — не нужен для сборки,
            # его metalink недоступен из РФ.
            echo "=== Отключаю fedora-cisco-openh264 ==="
            for repo in /etc/yum.repos.d/fedora-cisco-openh264.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            # === Шаг B: отключение AMD ROCm-репозитория ===
            # stable.repo.amd.com недоступен из РФ (timeout >30s).
            # ROCm уже вшит в образ.
            echo "=== Отключаю AMD ROCm-репозиторий ==="
            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            # === Шаг C: установка инструментов сборки ===
            if command -v dnf5 >/dev/null 2>&1; then
              echo "=== Установка gcc-c++, make, git через dnf5 ==="
              dnf5 install -y --setopt=install_weak_deps=False \
                gcc-c++ make git
            elif command -v microdnf >/dev/null 2>&1; then
              microdnf install -y --setopt=install_weak_deps=0 \
                gcc-c++ make git
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y --setopt=install_weak_deps=False \
                gcc-c++ make git
            else
              echo "Неизвестный пакетный менеджер." >&2
              exit 1
            fi

            # === Шаг D: setup.sh ===
            cd /opt/Strata && ./setup.sh
          '

        echo
        echo "Установка завершена."
        echo "Всё лежит в: $STRATA_DIR"
        echo "Запуск сервера: strata-start"
      '';
    })

    # =====================================================================
    # Сервисный контейнер. Использует готовый движок из ~/llm/strata.
    # Создаётся один раз, потом только start/stop.
    #
    # Команда запуска сервера (`./start.sh --host ... --port ...`) —
    # предположение. Проверьте после setup: ls ~/llm/strata/*.sh
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="strata-server"
        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена в $STRATA_DIR" >&2
          echo "Сначала выполните: strata-setup" >&2
          exit 1
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
            -v "$STRATA_DIR:/opt/Strata:Z" \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c "cd /opt/Strata && exec ./start.sh --host 0.0.0.0 --port ${toString portContainer}"
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
      name = "strata-stop";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="strata-server"

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
      name = "strata-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="strata-server"
        IMAGE="${image}"
        STRATA_DIR="${strataDir}"

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

        if [ -d "$STRATA_DIR" ]; then
          SIZE=$(du -sh "$STRATA_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $STRATA_DIR ($SIZE — исходники + модели)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$STRATA_DIR"
            echo "$STRATA_DIR удалён."
          else
            echo "$STRATA_DIR сохранён."
          fi
        fi
        echo "Готово."
      '';
    })

    # === Обновление ===
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "Обновляю исходники (git pull на хосте)..."
        git -C "$STRATA_DIR" pull --ff-only

        echo
        echo "Пересборка (setup.sh в контейнере)..."
        echo

        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -v "$STRATA_DIR:/opt/Strata:Z" \
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
              dnf5 install -y --setopt=install_weak_deps=False gcc-c++ make git
            elif command -v microdnf >/dev/null 2>&1; then
              microdnf install -y --setopt=install_weak_deps=0 gcc-c++ make git
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y --setopt=install_weak_deps=False gcc-c++ make git
            fi

            cd /opt/Strata && ./setup.sh
          '

        echo
        echo "Обновление завершено. Перезапустите сервер:"
        echo "  strata-stop && strata-start"
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    strata-setup = {
      name = "Strata Setup (first time)";
      exec = "strata-setup";
      icon = "system-software-install";
      terminal = true;
      categories = [ "Development" "Science" ];
    };
    strata-start = {
      name = "Strata Start (port ${toString portHost})";
      exec = "strata-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    strata-stop = {
      name = "Strata Stop";
      exec = "strata-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
