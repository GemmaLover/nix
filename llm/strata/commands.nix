{ config, pkgs, lib, strataConfig, ... }:

let
  inherit (strataConfig) image portHost portContainer strataDir;
in
{
  home.packages = [
    # =====================================================================
    # Одноразовая установка Strata. ИНТЕРАКТИВНАЯ.
    #
    # Использует `podman run --rm -it`: контейнер создаётся, выполняется
    # setup.sh (спрашивает модель/контекст/vision), после выхода
    # контейнер удаляется. Но ВСЁ, что setup.sh записал в /opt/Strata,
    # физически лежит в ~/llm/strata на хосте (bind mount) — не теряется.
    #
    # После успешного завершения: strata-start.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        mkdir -p "$STRATA_DIR"

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

        # --rm: удаляем контейнер после setup, чтобы не мусорить.
        # Всё ценное лежит в $STRATA_DIR (bind mount).
        # --entrypoint /bin/bash переопределяет entrypoint образа.
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
          -c "
            cd /opt/Strata
            if [ ! -d .git ]; then
              echo 'Клонирую Strata...'
              git clone https://github.com/Niko1221/Strata.git .
            else
              echo 'Strata уже есть, git pull...'
              git pull --ff-only || true
            fi
            ./setup.sh
          "

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
    # Entrypoint сервисного контейнера НЕ запускает setup.sh — только сервер.
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
          echo "Запускаю сервер..."
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

    # === Обновление (git pull + пересборка) ===
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "Обновляю Strata (git pull + setup.sh)..."
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
          -c "
            cd /opt/Strata && git pull --ff-only && ./setup.sh
          "

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
