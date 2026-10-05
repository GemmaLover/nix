{ config, pkgs, lib, cockpitConfig, ... }:

let
  inherit (cockpitConfig) rocm vulkan modelsDir modelsIniTemplate ai-toolbox-cockpit;
in
{
  # =====================================================================
  # Шаблон models.ini.example через home.file.
  #
  # home.file — декларативный механизм HM, работает надёжнее home.activation
  # (последняя иногда не выполняется при nixos-rebuild switch, если
  # home-manager-lexi.service не перезапускается).
  #
  # Файл .example перезаписывается при каждом rebuild — это шаблон,
  # не пользовательские данные. Пользовательский models.ini создаётся
  # автоматически при первом запуске контейнера (см. llama-*-start ниже).
  # =====================================================================
  home.file."llm/models/llama-cpp/models.ini.example".source = modelsIniTemplate;

  home.packages = [
    ai-toolbox-cockpit

    # === Обновление ai-toolbox-cockpit ===
    (pkgs.writeShellApplication {
      name = "ai-toolbox-cockpit-update";
      runtimeInputs = [ pkgs.nix-prefetch-github pkgs.jq pkgs.gnugrep pkgs.gnused pkgs.coreutils ];
      text = ''
        set -euo pipefail

        PKG_FILE="$HOME/projects/nix-wrap/nix/pkgs/ai-toolbox-cockpit/default.nix"

        if [ ! -f "$PKG_FILE" ]; then
          echo "Не найден файл пакета: $PKG_FILE" >&2
          exit 1
        fi

        echo "Запрашиваю свежий хэш main-ветки kyuz0/ai-toolbox-cockpit..."
        NEW_JSON=$(nix-prefetch-github kyuz0 ai-toolbox-cockpit --rev main --json)
        NEW_HASH=$(echo "$NEW_JSON" | jq -r '.hash')
        NEW_REV=$(echo "$NEW_JSON" | jq -r '.rev')

        OLD_HASH=$(grep -oE 'sha256-[A-Za-z0-9+/=]+' "$PKG_FILE" | head -1)

        echo
        echo "Старый хэш: $OLD_HASH"
        echo "Новый хэш:  $NEW_HASH  (commit $NEW_REV)"
        echo

        if [ "$OLD_HASH" = "$NEW_HASH" ]; then
          echo "Обновление не требуется — main уже зафиксирован."
          exit 0
        fi

        read -r -p "Заменить хэш в $PKG_FILE и запустить n13rebuild? [y/N] " answer
        if [[ "''${answer,,}" != "y" ]]; then
          echo "Отменено. Замените хэш вручную:"
          echo "  hash = \"$NEW_HASH\";"
          exit 0
        fi

        sed -i "s|$OLD_HASH|$NEW_HASH|" "$PKG_FILE"
        echo "Хэш обновлён. Запускаю n13rebuild..."
        n13rebuild "chore(cockpit): bump ai-toolbox-cockpit to $NEW_REV"
      '';
    })

    # === Сброс состояния ai-toolbox-cockpit ===
    (pkgs.writeShellApplication {
      name = "ai-toolbox-cockpit-clean";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        set -euo pipefail

        DIRS=(
          "$HOME/.config/ai-toolbox-cockpit"
          "$HOME/.local/share/ai-toolbox-cockpit"
          "$HOME/.cache/ai-toolbox-cockpit"
        )

        FOUND=0
        for d in "''${DIRS[@]}"; do
          if [ -d "$d" ]; then
            SIZE=$(du -sh "$d" 2>/dev/null | cut -f1 || echo "?")
            echo "Найдено: $d ($SIZE)"
            FOUND=1
          fi
        done

        if [ "$FOUND" -eq 0 ]; then
          echo "Нечего чистить — состояния ai-toolbox-cockpit нет."
          exit 0
        fi

        read -r -p "Удалить эти директории? [y/N] " answer
        if [[ "''${answer,,}" != "y" ]]; then
          echo "Отменено."
          exit 0
        fi

        for d in "''${DIRS[@]}"; do
          rm -rf "$d"
        done
        echo "Состояние ai-toolbox-cockpit очищено. Модели сохранены."
      '';
    })

    # === ROCm контейнер ===
    (pkgs.writeShellApplication {
      name = "llama-rocm-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="${rocm.containerName}"
        IMAGE="${rocm.image}"
        PORT_HOST=${toString rocm.portHost}
        PORT_CONTAINER=${toString rocm.portContainer}
        MODELS_DIR="${modelsDir}"
        INI_FILE="$MODELS_DIR/models.ini"
        INI_EXAMPLE="$MODELS_DIR/models.ini.example"

        mkdir -p "$MODELS_DIR"

        # Создаём models.ini из шаблона при первом запуске.
        # Шаблон .example обновляется декларативно через home.file при
        # каждом rebuild. Если models.ini уже существует — не трогаем
        # (пользовательские правки сохраняются).
        if [ ! -f "$INI_FILE" ]; then
          if [ ! -f "$INI_EXAMPLE" ]; then
            echo "ОШИБКА: не найден $INI_EXAMPLE" >&2
            echo "Пересоберите систему: n13rebuild" >&2
            exit 1
          fi
          cp "$INI_EXAMPLE" "$INI_FILE"
          echo "Создан $INI_FILE из шаблона."
          echo "Отредактируйте его под свои модели: nano $INI_FILE"
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
            echo "Образ '$IMAGE' отсутствует. Скачиваю (~1.3 ГБ)..."
            podman pull "$IMAGE"
          fi

          # --entrypoint /bin/bash — переопределяем ENTRYPOINT образа,
          # чтобы самим запустить llama-server с --models-preset.
          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$MODELS_DIR:/models:Z" \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c "llama-server --models-preset /models/models.ini"

          echo "Контейнер создан. Запускаю..."
          podman start "$CONTAINER_NAME"
        fi

        URL="http://localhost:$PORT_HOST"
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
    })

    (pkgs.writeShellApplication {
      name = "llama-rocm-stop";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="${rocm.containerName}"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' не найден."
          exit 0
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю (статус: $STATUS)..."
            podman stop -t 30 "$CONTAINER_NAME" 2>/dev/null || {
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

    (pkgs.writeShellApplication {
      name = "llama-rocm-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="${rocm.containerName}"
        IMAGE="${rocm.image}"

        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ '$IMAGE' (~1.3 ГБ)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            podman rmi "$IMAGE"
            echo "Образ удалён."
          else
            echo "Образ сохранён."
          fi
        fi
        echo "Готово."
      '';
    })

    # === Vulkan контейнер ===
    (pkgs.writeShellApplication {
      name = "llama-vulkan-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="${vulkan.containerName}"
        IMAGE="${vulkan.image}"
        PORT_HOST=${toString vulkan.portHost}
        PORT_CONTAINER=${toString vulkan.portContainer}
        MODELS_DIR="${modelsDir}"
        INI_FILE="$MODELS_DIR/models.ini"
        INI_EXAMPLE="$MODELS_DIR/models.ini.example"

        mkdir -p "$MODELS_DIR"

        # Создаём models.ini из шаблона при первом запуске.
        # См. комментарий в llama-rocm-start.
        if [ ! -f "$INI_FILE" ]; then
          if [ ! -f "$INI_EXAMPLE" ]; then
            echo "ОШИБКА: не найден $INI_EXAMPLE" >&2
            echo "Пересоберите систему: n13rebuild" >&2
            exit 1
          fi
          cp "$INI_EXAMPLE" "$INI_FILE"
          echo "Создан $INI_FILE из шаблона."
          echo "Отредактируйте его под свои модели: nano $INI_FILE"
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
            echo "Образ '$IMAGE' отсутствует. Скачиваю (~573 МБ)..."
            podman pull "$IMAGE"
          fi

          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/dri \
            --group-add video \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$MODELS_DIR:/models:Z" \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c "llama-server --models-preset /models/models.ini"

          echo "Контейнер создан. Запускаю..."
          podman start "$CONTAINER_NAME"
        fi

        URL="http://localhost:$PORT_HOST"
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
    })

    (pkgs.writeShellApplication {
      name = "llama-vulkan-stop";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="${vulkan.containerName}"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' не найден."
          exit 0
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю (статус: $STATUS)..."
            podman stop -t 30 "$CONTAINER_NAME" 2>/dev/null || {
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

    (pkgs.writeShellApplication {
      name = "llama-vulkan-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="${vulkan.containerName}"
        IMAGE="${vulkan.image}"

        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ '$IMAGE' (~573 МБ)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            podman rmi "$IMAGE"
            echo "Образ удалён."
          else
            echo "Образ сохранён."
          fi
        fi
        echo "Готово."
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    ai-toolbox-cockpit = {
      name = "AI Toolbox Cockpit";
      genericName = "TUI for managing AI containers";
      exec = "ai-toolbox-cockpit";
      icon = "utilities-terminal";
      terminal = true;
      categories = [ "Development" "Science" ];
    };
    llama-rocm-start = {
      name = "llama.cpp ROCm Start (port 8085)";
      exec = "llama-rocm-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    llama-rocm-stop = {
      name = "llama.cpp ROCm Stop";
      exec = "llama-rocm-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    llama-vulkan-start = {
      name = "llama.cpp Vulkan Start (port 8086)";
      exec = "llama-vulkan-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    llama-vulkan-stop = {
      name = "llama.cpp Vulkan Stop";
      exec = "llama-vulkan-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
