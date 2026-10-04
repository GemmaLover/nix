# Команды управления контейнером Unsloth (AMD ROCm).
#
# Запуск:      unsloth-start   — создаёт контейнер (если нет) и открывает веб-UI
# Остановка:   unsloth-stop    — останавливает контейнер (volume и модели сохраняются)
# Удаление:    unsloth-remove  — удаляет контейнер, volume и папку моделей (с подтверждением)
#
# Контейнер создаётся при первом запуске. Отдельного unsloth-install нет —
# это сознательное упрощение: создание и запуск объединены в unsloth-start.
#
# GPU-доступ: rootless Podman требует --device /dev/kfd, --device /dev/dri
# и --group-add keep-groups (только для crun runtime). Пользователь lexi
# должен быть в группах video и render — это настраивается в llm/system.nix.
{ config, pkgs, lib, unslothConfig, ... }:

let
  inherit (unslothConfig) image portHost portContainer dataVolume hostProjects hfCache;
in
{
  home.packages = [
    # --- Запуск / создание ---
    (pkgs.writeShellApplication {
      name = "unsloth-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="unsloth"
        IMAGE="${image}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}
        DATA_VOLUME="${dataVolume}"
        HOST_PROJECTS="${hostProjects}"
        HF_CACHE="${hfCache}"

        if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' уже существует."
          STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
          if [ "$STATUS" = "running" ]; then
            echo "Уже запущен."
          else
            echo "Запускаю..."
            podman start "$CONTAINER_NAME"
          fi
        else
          echo "Контейнер не найден. Создаю..."
          if ! podman image exists "$IMAGE" 2>/dev/null; then
            echo "Образ '$IMAGE' не найден. Скачиваю (может занять время)..."
            podman pull "$IMAGE"
          fi
          if ! podman volume exists "$DATA_VOLUME" 2>/dev/null; then
            podman volume create "$DATA_VOLUME"
            echo "Создан volume '$DATA_VOLUME'."
          fi
          mkdir -p "$HF_CACHE"
          echo "Кэш моделей: $HF_CACHE"

          # Создаём контейнер с теми же параметрами, что были в старом
          # unsloth-install: GPU-устройства, keep-groups, shm-size, монтирования.
          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$HOST_PROJECTS:/workspace/host:Z" \
            -v "$DATA_VOLUME:/workspace/studio" \
            -v "$HF_CACHE:/workspace/.cache/huggingface:Z" \
            -e JUPYTER_PASSWORD=unsloth \
            -e HF_HOME=/workspace/.cache/huggingface \
            "$IMAGE"

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

    # --- Остановка ---
    (pkgs.writeShellApplication {
      name = "unsloth-stop";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="unsloth"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер '$CONTAINER_NAME' не найден — нечего останавливать."
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
          exited|stopped|created)
            echo "Уже остановлен (статус: $STATUS)."
            ;;
          *)
            echo "Неизвестный статус: $STATUS"
            ;;
        esac
        echo "Готово."
      '';
    })

    # --- Удаление ---
    (pkgs.writeShellApplication {
      name = "unsloth-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="unsloth"
        DATA_VOLUME="${dataVolume}"
        IMAGE="${image}"
        HF_CACHE="${hfCache}"

        if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Удаляю контейнер '$CONTAINER_NAME'..."
          podman rm -f "$CONTAINER_NAME"
        else
          echo "Контейнер '$CONTAINER_NAME' уже отсутствует."
        fi

        if podman volume exists "$DATA_VOLUME" 2>/dev/null; then
          read -r -p "Удалить volume '$DATA_VOLUME' (настройки Studio)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            podman volume rm "$DATA_VOLUME"
            echo "Volume удалён."
          else
            echo "Volume сохранён."
          fi
        fi

        if [ -d "$HF_CACHE" ]; then
          SIZE=$(du -sh "$HF_CACHE" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить папку моделей '$HF_CACHE' ($SIZE)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$HF_CACHE"
            echo "Папка моделей удалена."
          else
            echo "Папка моделей сохранена."
          fi
        fi

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ '$IMAGE' (~10 ГБ)? [y/N] " answer
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
    unsloth-start = {
      name = "Unsloth Start";
      exec = "unsloth-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    unsloth-stop = {
      name = "Unsloth Stop";
      exec = "unsloth-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
