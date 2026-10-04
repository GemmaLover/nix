{ config, pkgs, ... }:

let
  # =====================================================================
  # Unsloth — контейнер для тонкой настройки и инференса LLM на AMD GPU.
  #
  # Скрипты:
  #   unsloth-install           — создать контейнер (одноразово)
  #   unsloth-start             — запустить и открыть веб-интерфейс
  #   unsloth-stop              — остановить (volume сохраняется)
  #   unsloth-remove            — удалить контейнер (volume и образ по выбору)
  #   unsloth-reset-password    — сбросить пароль веб-интерфейса
  #   unsloth-check-update      — проверить, есть ли новый образ
  #   unsloth-update            — применить обновление
  #
  # Каждый скрипт получает только те переменные, которые использует —
  # это требование shellcheck (SC2034: unused variable).
  #
  # ВАЖНО: везде используем `podman inspect --format '{{.State.Status}}'`
  # вместо `podman container running` — в rootless-режиме последний
  # возвращает устаревший статус (false для реально работающего контейнера).
  #
  # Веб-интерфейс Unsloth Studio слушает 8000 внутри контейнера,
  # наружу проброшен на 8005. Внешний порт задаётся в PORT_HOST.
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
      # Папка для моделей HuggingFace на хосте.
      # Монтируется в контейнер как /workspace/.cache/huggingface,
      # чтобы модели оставались на диске даже после удаления контейнера.
      HF_CACHE="''${HOME}/llm/models"
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

      # Создаём папку для моделей, если её ещё нет.
      mkdir -p "$HF_CACHE"
      echo "Кэш моделей HuggingFace: $HF_CACHE"

      # --shm-size=8g: ROCm/PyTorch требуют большую shared memory,
      #                иначе падают при работе с моделями.
      # Внутренний порт 8000 пробрасываем на внешний 8005.
      #
      # Монтирования:
      #   ~/projects       → /workspace/host       (проекты пользователя)
      #   volume unsloth-data → /workspace/studio   (данные Studio)
      #   ~/llm/models     → /workspace/.cache/huggingface (кэш моделей)
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
      echo "  unsloth-check-update     — проверить обновление образа"
      echo "  unsloth-update           — применить обновление"
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

      # Читаем реальный статус через inspect.
      # podman container running в rootless иногда врёт.
      STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
      if [ "$STATUS" = "running" ]; then
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
  # ВАЖНО: не используем `podman container running` — в rootless-режиме
  # он иногда возвращает устаревший статус (false для реально
  # работающего контейнера). Читаем статус через inspect.
  unslothStop = pkgs.writeShellApplication {
    name = "unsloth-stop";
    runtimeInputs = [ pkgs.podman pkgs.procps pkgs.coreutils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден — нечего останавливать."
        exit 0
      fi

      # Реальный статус — через inspect.
      STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")

      case "$STATUS" in
        running|paused|restarting)
          echo "Контейнер в состоянии '$STATUS' — останавливаю..."
          podman stop -t 30 "$CONTAINER_NAME" 2>/dev/null || {
            echo "SIGTERM не сработал, убиваю принудительно (SIGKILL)..."
            podman kill "$CONTAINER_NAME" 2>/dev/null || true
            sleep 2
            STILL=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Running}}' 2>/dev/null || echo "false")
            if [ "$STILL" = "true" ]; then
              echo "Всё ещё жив — удаляю принудительно..."
              podman rm -f "$CONTAINER_NAME" || true
            fi
          }
          ;;
        exited|stopped|created)
          echo "Контейнер уже в состоянии '$STATUS'."
          ;;
        *)
          echo "Неизвестный статус: $STATUS"
          ;;
      esac

      echo "Готово."
    '';
  };

  # --- Удаление (с подтверждениями для volume, моделей и образа) ---
  unslothRemove = pkgs.writeShellApplication {
    name = "unsloth-remove";
    runtimeInputs = [ pkgs.podman pkgs.coreutils pkgs.procps ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      DATA_VOLUME="unsloth-data"
      IMAGE="docker.io/unsloth/unsloth-rocm:studio"
      # Папка с моделями HuggingFace на хосте. Монтируется в контейнер
      # как /workspace/.cache/huggingface. Не удаляем её без явного
      # подтверждения — там могут быть десятки гигабайт моделей.
      HF_CACHE="''${HOME}/llm/models"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Удаляю контейнер '$CONTAINER_NAME'..."
        podman rm -f "$CONTAINER_NAME"
      else
        echo "Контейнер '$CONTAINER_NAME' уже отсутствует."
      fi

      if podman volume exists "$DATA_VOLUME" 2>/dev/null; then
        read -r -p "Удалить volume '$DATA_VOLUME' (настройки Unsloth Studio)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          podman volume rm "$DATA_VOLUME"
          echo "Volume удалён."
        else
          echo "Volume сохранён."
        fi
      fi

      # Папку с моделями удаляем только по явному подтверждению.
      # Показываем её размер, чтобы понимать, что теряем.
      if [ -d "$HF_CACHE" ]; then
        SIZE=$(du -sh "$HF_CACHE" 2>/dev/null | cut -f1 || echo "?")
        read -r -p "Удалить папку моделей '$HF_CACHE' ($SIZE)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          rm -rf "$HF_CACHE"
          echo "Папка моделей удалена."
        else
          echo "Папка моделей сохранена."
        fi
      else
        echo "Папка моделей '$HF_CACHE' не найдена — нечего удалять."
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

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден."
        echo "Запустите его: unsloth-start"
        exit 1
      fi

      # Реальный статус — через inspect.
      STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
      if [ "$STATUS" != "running" ]; then
        echo "Контейнер '$CONTAINER_NAME' не запущен (статус: $STATUS)."
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

  # --- Проверка обновления образа (без изменений) ---
  unslothCheckUpdate = pkgs.writeShellApplication {
    name = "unsloth-check-update";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      IMAGE="docker.io/unsloth/unsloth-rocm:studio"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден. Сначала: unsloth-install"
        exit 1
      fi

      OLD_ID=$(podman inspect --format '{{.Image}}' "$CONTAINER_NAME")
      echo "Текущий образ (у контейнера): $OLD_ID"
      echo -n "Проверяю реестр... "
      podman pull --quiet "$IMAGE" >/dev/null
      NEW_ID=$(podman image inspect --format '{{.Id}}' "$IMAGE")
      echo "готово."
      echo "Свежий образ (в реестре):     $NEW_ID"

      if [ "$OLD_ID" = "$NEW_ID" ]; then
        echo
        echo "Обновление не требуется — установлена последняя версия."
      else
        echo
        echo "Доступно обновление."
        echo "Применить: unsloth-update"
      fi
    '';
  };

  # --- Обновление образа и пересоздание контейнера ---
  unslothUpdate = pkgs.writeShellApplication {
    name = "unsloth-update";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="unsloth"
      IMAGE="docker.io/unsloth/unsloth-rocm:studio"
      DATA_VOLUME="unsloth-data"
      HOST_PROJECTS="''${HOME}/projects"
      # Папка для моделей HuggingFace на хосте (та же, что в install).
      HF_CACHE="''${HOME}/llm/models"
      PORT_HOST=8005
      PORT_CONTAINER=8000

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден. Сначала: unsloth-install"
        exit 1
      fi

      # Запоминаем старый образ, чтобы понять, изменился ли он.
      OLD_ID=$(podman inspect --format '{{.Image}}' "$CONTAINER_NAME")
      echo "Текущий образ: $OLD_ID"

      # Скачиваем свежий образ. Если тег не изменился, pull завершится
      # быстро (все слои уже есть локально).
      echo "Проверяю реестр..."
      podman pull --quiet "$IMAGE" >/dev/null
      NEW_ID=$(podman image inspect --format '{{.Id}}' "$IMAGE")
      echo "Свежий образ:  $NEW_ID"

      if [ "$OLD_ID" = "$NEW_ID" ]; then
        echo
        echo "Обновление не требуется — установлена последняя версия."
        exit 0
      fi

      echo
      echo "Доступно обновление: $OLD_ID -> $NEW_ID"
      read -r -p "Применить обновление сейчас? Контейнер будет пересоздан, volume сохранится. [y/N] " answer
      if [[ "''${answer,,}" != "y" ]]; then
        echo "Отменено."
        exit 0
      fi

      # Останавливаем и удаляем старый контейнер. Volume НЕ трогаем.
      echo "Останавливаю и удаляю старый контейнер..."
      podman rm -f "$CONTAINER_NAME"

      # Пересоздаём контейнер с теми же параметрами, что в unsloth-install.
      # Не забываем про HF_CACHE — иначе модели будут качаться в контейнер.
      echo "Создаю новый контейнер..."
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

      echo
      echo "Обновление завершено."
      echo "Запуск: unsloth-start"
    '';
  };

in
{
  # === Пользовательские команды ===
  home.packages = [
    unslothInstall
    unslothStart
    unslothStop
    unslothRemove
    unslothResetPassword
    unslothCheckUpdate
    unslothUpdate
  ];

  # === Ярлыки в меню приложений ===
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
