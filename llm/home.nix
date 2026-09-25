{ config, pkgs, ... }:

let
  # =====================================================================
  # Unsloth — контейнер для тонкой настройки и инференса LLM на AMD GPU.
  # Скрипты разделены по назначению: install / start / stop / remove.
  # Каждый скрипт получает только те переменные, которые использует —
  # это требование shellcheck (SC2034: unused variable).
  # =====================================================================

  # --- Установка (одноразово) ---
  unslothInstall = pkgs.writeShellApplication {
    name = "unsloth-install";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      IMAGE="docker.io/unsloth/unsloth:latest"
      DATA_VOLUME="unsloth-data"
      HOST_PROJECTS="''${HOME}/projects"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' уже существует."
        echo "Для пересоздания сначала запустите unsloth-remove."
        exit 1
      fi

      if podman image exists "$IMAGE" 2>/dev/null; then
        echo "Образ '$IMAGE' уже есть локально."
      else
        echo "Образ '$IMAGE' не найден локально."
        read -r -p "Скачать его сейчас (~5-7 ГБ)? [y/N] " answer
        if [[ "''${answer,,}" != "y" ]]; then
          echo "Отменено."
          exit 1
        fi
        podman pull "$IMAGE"
      fi

      if ! podman volume exists "$DATA_VOLUME" 2>/dev/null; then
        podman volume create "$DATA_VOLUME"
        echo "Создан volume '$DATA_VOLUME'."
      fi

      podman create \
        --name "$CONTAINER_NAME" \
        --device /dev/kfd \
        --device /dev/dri \
        --group-add keep-groups \
        --security-opt label=disable \
        -p 8888:8888 \
        -p 8000:8000 \
        -v "$HOST_PROJECTS:/workspace/host:Z" \
        -v "$DATA_VOLUME:/workspace/studio" \
        -e JUPYTER_PASSWORD=unsloth \
        "$IMAGE"

      echo
      echo "Контейнер '$CONTAINER_NAME' создан."
      echo "Запуск:    unsloth-start"
      echo "Остановка: unsloth-stop"
      echo "Удаление:  unsloth-remove"
    '';
  };

  # --- Запуск ---
  unslothStart = pkgs.writeShellApplication {
    name = "unsloth-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден." >&2
        echo "Сначала запустите: unsloth-install" >&2
        exit 1
      fi

      if podman container running "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже запущен."
      else
        echo "Запускаю контейнер..."
        podman start "$CONTAINER_NAME"
      fi

      echo -n "Ожидание сервиса"
      for _ in {1..60}; do
        if curl -fsS -o /dev/null "http://localhost:8000" 2>/dev/null; then
          echo " — готов."
          break
        fi
        echo -n "."
        sleep 1
      done

      echo "Открываю http://localhost:8000"
      xdg-open "http://localhost:8000" &
    '';
  };

  # --- Остановка ---
  unslothStop = pkgs.writeShellApplication {
    name = "unsloth-stop";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден — нечего останавливать."
        exit 0
      fi

      if ! podman container running "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже остановлен."
        exit 0
      fi

      echo "Останавливаю контейнер..."
      podman stop "$CONTAINER_NAME"
      echo "Готово."
    '';
  };

  # --- Удаление (с подтверждениями для volume и образа) ---
  unslothRemove = pkgs.writeShellApplication {
    name = "unsloth-remove";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      DATA_VOLUME="unsloth-data"
      IMAGE="docker.io/unsloth/unsloth:latest"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Удаляю контейнер '$CONTAINER_NAME'..."
        podman rm -f "$CONTAINER_NAME"
      else
        echo "Контейнер '$CONTAINER_NAME' уже отсутствует."
      fi

      if podman volume exists "$DATA_VOLUME" 2>/dev/null; then
        read -r -p "Удалить volume '$DATA_VOLUME' (модели и настройки)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          podman volume rm "$DATA_VOLUME"
          echo "Volume удалён."
        else
          echo "Volume сохранён."
        fi
      fi

      if podman image exists "$IMAGE" 2>/dev/null; then
        read -r -p "Удалить образ '$IMAGE' (~5-7 ГБ)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          podman rmi "$IMAGE"
          echo "Образ удалён."
        else
          echo "Образ сохранён."
        fi
      fi

      echo "Готово."
    '';
  };

in
{
  home.packages = [
    unslothInstall
    unslothStart
    unslothStop
    unslothRemove
  ];

  xdg.desktopEntries = {
    unsloth-start = {
      name = "Unsloth Start";
      genericName = "Start Unsloth LLM container";
      exec = "unsloth-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    unsloth-stop = {
      name = "Unsloth Stop";
      genericName = "Stop Unsloth LLM container";
      exec = "unsloth-stop";
      icon = "process-stop";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
