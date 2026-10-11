{ config, pkgs, lib, strataConfig, ... }:

let
  inherit (strataConfig) image portHost portContainer strataDir;
in
{
  home.packages = [
    # =====================================================================
    # Одноразовая установка Strata. ИНТЕРАКТИВНАЯ.
    #
    # ВАЖНО: в образе kyuz0/amd-strix-halo-toolboxes НЕТ git.
    # Поэтому репозиторий клонируется НА ХОСТЕ (где git есть),
    # а внутрь контейнера монтируется готовое дерево через bind mount.
    #
    # Порядок:
    #   1. git clone на хосте → ~/llm/strata
    #   2. podman run --rm -it с монтированием ~/llm/strata → /opt/Strata
    #   3. Внутри контейнера: cd /opt/Strata && ./setup.sh
    #
    # setup.sh спросит модель (IQ2_XS, Q4_K_M, ...), контекст, vision.
    # Когда спросит путь для моделей — указывать /opt/Strata/models
    # (это = ~/llm/strata/models на хосте).
    #
    # После выхода контейнер удаляется (--rm), но ВСЁ остаётся в
    # ~/llm/strata: исходники, скомпилированный движок, модели.
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

        # === Шаг 1: клонируем/обновляем Strata НА ХОСТЕ ===
        # В образе kyuz0 нет git — поэтому клонируем здесь, где git есть.
        # Дальше монтируем готовое дерево в контейнер.
        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Клонирую Strata в $STRATA_DIR..."
          git clone https://github.com/Niko1221/Strata.git "$STRATA_DIR"
        else
          echo "Обновляю Strata (git pull)..."
          git -C "$STRATA_DIR" pull --ff-only || echo "  (git pull пропущен)"
        fi

        if [ ! -x "$STRATA_DIR/setup.sh" ]; then
          echo "ОШИБКА: в $STRATA_DIR нет setup.sh" >&2
          echo "Проверьте содержимое: ls $STRATA_DIR" >&2
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
        echo "  (это то же самое, что $STRATA_DIR/models на хосте)"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        # === Шаг 2: запускаем setup.sh ВНУТРИ контейнера ===
        # Репозиторий уже на месте (через bind mount), поэтому git не нужен.
        # -it для интерактивного setup.sh.
        # --rm: контейнер удаляется после setup, всё ценное в $STRATA_DIR.
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
          -c "cd /opt/Strata && ./setup.sh"

        echo
        echo "Установка завершена."
        echo "Всё лежит в: $STRATA_DIR"
        echo "Запуск сервера: strata-start"
      '';
    })

    # =====================================================================
    # Сервисный контейнер. Использует уже собранный движок из ~/llm/strata.
    #
    # Создаётся один раз (при первом вызове), потом только start/stop.
    # Entrypoint НЕ запускает setup.sh — только сервер.
    #
    # Если в репозитории Strata нет start.sh — замените команду в
    # entrypoint на ту, что описана в README проекта (например,
    # `python -m strata.server` или `./build/strata-server`).
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
    # Плавно шлёт SIGTERM, ждёт до 60 секунд. Если не сработало — SIGKILL.
    # Файлы в ~/llm/strata не затрагиваются.
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
    # Удаляет контейнер, опционально образ, опционально ~/llm/strata
    # (исходники + модели). Спрашивает подтверждение на каждый шаг.
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

    # === Обновление (git pull + пересборка) ===
    # Клонирование и pull делает ХОСТ (где есть git), в контейнере
    # запускается только setup.sh — та же схема, что в strata-setup.
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
        echo "setup.sh снова спросит модель — можно оставить ту же."
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
          -c "cd /opt/Strata && ./setup.sh"

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
      terminal = true;   # setup интерактивный, нужен терминал
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
