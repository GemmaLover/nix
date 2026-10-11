{ config, pkgs, lib, gufoConfig, ... }:

let
  inherit (gufoConfig) image portHost portContainer modelsDir mainModel apiKeyFile;
in
{
  home.packages = [
    # =====================================================================
    # Запуск Gufo.
    #
    # API-ключ читается из файла apiKeyFile (~/.config/gufo/api-key) и
    # передаётся в контейнер через env Gufo_API_KEY и флаг --api-key.
    # Не хранится в git, не попадает в nix store.
    #
    # Если файла нет — скрипт откажется запускаться и покажет, как создать.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "gufo-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="gufo"
        IMAGE="${image}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}
        MODELS_DIR="${modelsDir}"
        MAIN_MODEL="${mainModel}"
        API_KEY_FILE="${apiKeyFile}"

        # === Проверка API-ключа ===
        if [ ! -f "$API_KEY_FILE" ]; then
          echo "ОШИБКА: нет файла с API-ключом: $API_KEY_FILE" >&2
          echo >&2
          echo "Создайте его один раз:" >&2
          echo "  mkdir -p $(dirname "$API_KEY_FILE")" >&2
          echo "  echo 'ваш-секретный-ключ' > $API_KEY_FILE" >&2
          echo "  chmod 600 $API_KEY_FILE" >&2
          exit 1
        fi

        API_KEY="$(cat "$API_KEY_FILE")"
        if [ -z "$API_KEY" ]; then
          echo "ОШИБКА: файл $API_KEY_FILE пустой." >&2
          exit 1
        fi

        # === Проверка модели ===
        # MAIN_MODEL — путь внутри контейнера (/models/...).
        # На хосте это $MODELS_DIR/<относительный путь>.
        MAIN_ON_HOST="$MODELS_DIR/''${MAIN_MODEL#/models/}"
        if [ ! -f "$MAIN_ON_HOST" ]; then
          echo "ОШИБКА: не найдена модель: $MAIN_ON_HOST" >&2
          echo "Проверьте, что файл на месте:" >&2
          echo "  ls -lh $MODELS_DIR/ISTA-DASLab/q2_0/" >&2
          exit 1
        fi

        # Gufo сам подтянет -00002-of-00002 по имени первого файла,
        # но проверим, что он тоже есть.
        MAIN_DIR=$(dirname "$MAIN_ON_HOST")
        if ! ls "$MAIN_DIR"/*-00002-of-00002.gguf >/dev/null 2>&1; then
          echo "ВНИМАНИЕ: второй шард (-00002-of-00002) не найден в $MAIN_DIR" >&2
          echo "Если модель разбита на две части, нужны оба файла." >&2
          echo
          read -r -p "Продолжить? [y/N] " answer
          [[ "''${answer,,}" == "y" ]] || exit 1
        fi

        if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
          if [ "$STATUS" = "running" ]; then
            echo "Контейнер '$CONTAINER_NAME' уже запущен."
          else
            echo "Запускаю существующий контейнер (статус: $STATUS)..."
            podman start "$CONTAINER_NAME"
          fi
        else
          echo "Контейнер не найден. Создаю..."
          if ! podman image exists "$IMAGE" 2>/dev/null; then
            echo "Образ '$IMAGE' отсутствует. Скачиваю..."
            podman pull "$IMAGE"
          fi

          # --api-key передаём как флаг gufo serve.
          # Если версия Gufo использует env Gufo_API_KEY — она тоже
          # прокинута через -e, на случай если флаг не поддерживается.
          podman create \
            --name "$CONTAINER_NAME" \
            --userns=keep-id:uid=1000,gid=1000 \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --ulimit memlock=-1 \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$MODELS_DIR:/models:ro" \
            -e Gufo_API_KEY="$API_KEY" \
            "$IMAGE" \
            gufo serve \
              --host 0.0.0.0 \
              --port "$PORT_CONTAINER" \
              --api-key "$API_KEY" \
              llm \
              --model "$MAIN_MODEL"

          echo "Контейнер создан. Запускаю..."
          podman start "$CONTAINER_NAME"
        fi

        URL="http://localhost:$PORT_HOST"
        echo -n "Ожидание сервиса (загрузка 125B-модели может занять минуты)"
        for _ in {1..900}; do
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
        CONTAINER_NAME="gufo"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' не найден."
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

    # === Логи ===
    (pkgs.writeShellApplication {
      name = "gufo-logs";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="gufo"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' не найден."
          exit 1
        fi

        exec podman logs -f "$CONTAINER_NAME"
      '';
    })

    # === Список моделей ===
    (pkgs.writeShellApplication {
      name = "gufo-models";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        set -euo pipefail
        MODELS_DIR="${modelsDir}"

        if [ ! -d "$MODELS_DIR" ]; then
          echo "Папки моделей нет: $MODELS_DIR"
          exit 0
        fi

        echo "Модели в: $MODELS_DIR"
        echo
        find "$MODELS_DIR" -name '*.gguf' -exec ls -lh {} \; 2>/dev/null | awk '{print $5, $9}'
      '';
    })

    # === Удаление ===
    (pkgs.writeShellApplication {
      name = "gufo-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="gufo"
        IMAGE="${image}"
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

        if [ -d "$MODELS_DIR/ISTA-DASLab" ]; then
          SIZE=$(du -sh "$MODELS_DIR/ISTA-DASLab" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить модели ISTA-DASLab ($SIZE)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$MODELS_DIR/ISTA-DASLab"
            echo "Модели удалены."
          else
            echo "Модели сохранены."
          fi
        fi
        echo "Готово."
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
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
