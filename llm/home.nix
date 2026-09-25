{ config, pkgs, ... }:

let
  # =====================================================================
  # Unsloth — контейнер для тонкой настройки и инференса LLM на AMD GPU.
  # Скрипты разделены по назначению: install / start / stop / remove / reset-password.
  # Каждый скрипт получает только те переменные, которые использует —
  # это требование shellcheck (SC2034: unused variable).
  #
  # Веб-интерфейс Unsloth Studio слушает 8000 внутри контейнера,
  # наружу проброшен на 8005 (внешний порт можно менять в PORT_HOST).
  # =====================================================================

  # --- Установка (одноразово) ---
  unslothInstall = pkgs.writeShellApplication {
    name = "unsloth-install";
    runtimeInputs = [ pkgs.podman pkgs.curl ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      IMAGE="docker.io/unsloth/unsloth-rocm:studio"
      DATA_VOLUME="unsloth-data"
      HOST_PROJECTS="''${HOME}/projects"
      PORT_HOST=8005
      PORT_CONTAINER=8000

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' уже существует."
        echo "Для пересоздания сначала запустите unsloth-remove."
        exit 1
      fi

      if podman image exists "$IMAGE" 2>/dev/null; then
        echo "Образ '$IMAGE' уже есть локально."
      else
        echo "Образ '$IMAGE' не найден локально."
        read -r -p "Скачать его сейчас (~10 ГБ)? [y/N] " answer
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

      # --shm-size=8g: ROCm/PyTorch требуют большую shared memory,
      #                иначе падают при работе с моделями.
      # Внутренний порт 8000 пробрасываем на внешний 8005.
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
        -e JUPYTER_PASSWORD=unsloth \
        "$IMAGE"

      echo
      echo "Контейнер '$CONTAINER_NAME' создан."
      echo "Запускаю контейнер для первичной настройки пароля..."
      podman start "$CONTAINER_NAME"

      echo -n "Ожидание сервиса Unsloth Studio"
      READY=0
      for _ in {1..90}; do
        if curl -fsS -o /dev/null "http://localhost:$PORT_HOST" 2>/dev/null; then
          echo " — готов."
          READY=1
          break
        fi
        echo -n "."
        sleep 1
      done

      if [ "$READY" -eq 0 ]; then
        echo " — сервис не поднялся за 90 секунд."
        echo "Проверьте логи: podman logs $CONTAINER_NAME"
        exit 1
      fi

      # Получаем пароль. Сначала пробуем reset-password,
      # если не сработает — читаем .bootstrap_password.
      echo
      echo "=================================================="
      echo "  Пароль для входа в Unsloth Studio"
      echo "  (имя пользователя: unsloth)"
      echo "=================================================="
      if podman exec "$CONTAINER_NAME" unsloth studio reset-password 2>/dev/null; then
        :
      elif podman exec "$CONTAINER_NAME" cat /opt/unsloth-studio/auth/.bootstrap_password 2>/dev/null; then
        :
      else
        echo "(не удалось получить пароль автоматически)"
        echo "Попробуйте вручную:"
        echo "  unsloth-reset-password"
      fi
      echo "=================================================="
      echo
      echo "Дальше:"
      echo "  unsloth-start            — открыть веб-интерфейс (http://localhost:$PORT_HOST)"
      echo "  unsloth-stop             — остановить контейнер"
      echo "  unsloth-remove           — удалить контейнер"
      echo "  unsloth-reset-password   — сбросить пароль веб-интерфейса"
    '';
  };

  # --- Запуск ---
  unslothStart = pkgs.writeShellApplication {
    name = "unsloth-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      PORT_HOST=8005
      URL="http://localhost:$PORT_HOST"

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
      IMAGE="docker.io/unsloth/unsloth-rocm:studio"

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
  };

  # --- Сброс пароля Unsloth Studio ---
  unslothResetPassword = pkgs.writeShellApplication {
    name = "unsloth-reset-password";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"

      if ! podman container running "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не запущен."
        echo "Запустите его: unsloth-start"
        exit 1
      fi

      echo "Сбрасываю пароль Unsloth Studio..."
      if podman exec "$CONTAINER_NAME" unsloth studio reset-password; then
        echo
        echo "Используйте этот пароль для входа (имя пользователя: unsloth)."
      else
        echo "Команда reset-password не сработала, читаю bootstrap-пароль..."
        podman exec "$CONTAINER_NAME" cat /opt/unsloth-studio/auth/.bootstrap_password
      fi
    '';
  };

in
{
  home.packages = [
    unslothInstall
    unslothStart
    unslothStop
    unslothRemove
    unslothResetPassword
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
