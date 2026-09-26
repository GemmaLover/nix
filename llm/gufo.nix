{ config, pkgs, ... }:

let
  # =====================================================================
  # Gufo — движок инференса для AMD Strix Halo (gfx1151).
  #
  # Использует Qwen3.8-27B с квантом UD-Q6_K_XL и DFlash2 драфтером.
  # Модели скачиваются через Hugging Face CLI.
  #
  # Скрипты:
  #   gufo-install  — скачать модели и создать контейнер
  #   gufo-start    — запустить сервер и открыть веб-интерфейс
  #   gufo-stop     — остановить контейнер
  #   gufo-remove   — удалить контейнер (модели по подтверждению)
  #   gufo-status   — проверить состояние моделей и контейнера
  #
  # Требования:
  #   - Пользователь в группах video и render (доступ к /dev/kfd, /dev/dri)
  #   - Параметры ядра: amd_iommu=off, amdgpu.gttsize=126976,
  #     ttm.pages_limit=32505856
  # =====================================================================

  CONTAINER_NAME = "gufo-qwen27b";
  IMAGE = "ghcr.io/gufo-org/toolboxes/gufo-runtime:latest";
  # Папка для моделей Gufo. Изолирована от Unsloth и других движков.
  MODELS_DIR = "\${HOME}/llm/models/gufo";
  # Внешний порт на хосте. Внутри контейнера Gufo слушает 8080.
  PORT_HOST = 8887;
  PORT_CONTAINER = 8080;

  # --- Установка (одноразово) ---
  gufoInstall = pkgs.writeShellApplication {
    name = "gufo-install";
    runtimeInputs = [
      pkgs.podman
      pkgs.curl
      pkgs.coreutils
      pkgs.python3Packages.huggingface-hub
    ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"
      IMAGE="${IMAGE}"
      MODELS_DIR="${MODELS_DIR}"
      PORT_HOST=${toString PORT_HOST}
      PORT_CONTAINER=${toString PORT_CONTAINER}

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' уже существует."
        echo "Для пересоздания запустите gufo-remove."
        exit 1
      fi

      echo "=== Скачивание моделей ==="
      mkdir -p "$MODELS_DIR"

      # --- Qwen3.8-27B (основная модель, Q6_K_XL) ---
      # Проверяем и наличие файла, и отсутствие .incomplete
      # (hf оставляет этот файл при прерванной загрузке).
      MODEL_MAIN="$MODELS_DIR/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K_XL.gguf"
      if [ -f "$MODEL_MAIN" ] && [ ! -f "$MODEL_MAIN.incomplete" ]; then
        SIZE=$(du -h "$MODEL_MAIN" | cut -f1)
        echo "Модель Qwen3.8-27B уже скачана ($SIZE)."
      else
        if [ -f "$MODEL_MAIN.incomplete" ]; then
          echo "Найден незавершённый файл — докачиваю с места обрыва."
        else
          echo "Скачиваю Qwen3.8-27B-UD-Q6_K_XL.gguf (~24 ГБ)..."
        fi
        hf download unsloth/Qwen3.8-27B-GGUF \
          Qwen3.8-27B-UD-Q6_K_XL.gguf \
          --revision 4ca720788d1e01f1bff70c033e0d0028fd02e502 \
          --repo-type model \
          --local-dir "$MODELS_DIR/Qwen3.8-27B-GGUF"
      fi

      # --- DFlash2 драфтер (Q4_K_M) ---
      MODEL_DRAFT="$MODELS_DIR/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
      if [ -f "$MODEL_DRAFT" ] && [ ! -f "$MODEL_DRAFT.incomplete" ]; then
        SIZE=$(du -h "$MODEL_DRAFT" | cut -f1)
        echo "DFlash2 драфтер уже скачан ($SIZE)."
      else
        if [ -f "$MODEL_DRAFT.incomplete" ]; then
          echo "Найден незавершённый файл — докачиваю с места обрыва."
        else
          echo "Скачиваю DFlash2 драфтер (~4 ГБ)..."
        fi
        hf download z-lab/Qwen3.8-27B-DFlash2-GGUF \
          Qwen3.8-27B-DFlash2-Q4_K_M.gguf \
          --revision 2d9571f8ce46e151f61c6499c99dee6079e1d610 \
          --repo-type model \
          --local-dir "$MODELS_DIR/Qwen3.8-27B-DFlash2-GGUF"
      fi

      echo
      echo "=== Создание Podman-контейнера ==="
      # --userns=keep-id — сохраняет UID/GID пользователя внутри контейнера.
      # --group-add keep-groups — сохраняет группы хоста (для /dev/kfd).
      # --ulimit memlock=-1 — снимает лимит на блокировку памяти (нужно для ROCm).
      # -v ...:/models:ro — монтируем папку с моделями только для чтения.
      # Порт: 8887 на хосте → 8080 внутри контейнера.
      podman create \
        --name "$CONTAINER_NAME" \
        --userns=keep-id:uid=1000,gid=1000 \
        --device /dev/kfd \
        --device /dev/dri \
        --group-add keep-groups \
        --ulimit memlock=-1 \
        --security-opt label=disable \
        -p "$PORT_HOST:$PORT_CONTAINER" \
        -v "$MODELS_DIR:/models:ro" \
        "$IMAGE" \
        gufo serve --host 0.0.0.0 --port "$PORT_CONTAINER" llm \
          --model /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K_XL.gguf \
          --speculative dflash2 \
          --dflash-model /models/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf

      echo
      echo "Контейнер '$CONTAINER_NAME' создан."
      echo "Модели:     $MODELS_DIR"
      echo "Запуск:     gufo-start"
      echo "Остановка:  gufo-stop"
      echo "Удаление:   gufo-remove"
      echo "Статус:     gufo-status"
      echo "Порт на хосте: $PORT_HOST"
    '';
  };

  # --- Запуск ---
  gufoStart = pkgs.writeShellApplication {
    name = "gufo-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"
      PORT_HOST=${toString PORT_HOST}
      URL="http://localhost:$PORT_HOST"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден." >&2
        echo "Сначала запустите: gufo-install" >&2
        exit 1
      fi

      if podman container running "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже запущен."
      else
        echo "Запускаю контейнер..."
        podman start "$CONTAINER_NAME"
      fi

      echo -n "Ожидание сервера Gufo"
      for _ in {1..120}; do
        if curl -fsS -o /dev/null "http://localhost:$PORT_HOST/health" 2>/dev/null; then
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
  gufoStop = pkgs.writeShellApplication {
    name = "gufo-stop";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"

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

  # --- Удаление ---
  gufoRemove = pkgs.writeShellApplication {
    name = "gufo-remove";
    runtimeInputs = [ pkgs.podman pkgs.coreutils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"
      IMAGE="${IMAGE}"
      MODELS_DIR="${MODELS_DIR}"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Удаляю контейнер '$CONTAINER_NAME'..."
        podman rm -f "$CONTAINER_NAME"
      else
        echo "Контейнер '$CONTAINER_NAME' уже отсутствует."
      fi

      # Папку с моделями удаляем только по явному подтверждению.
      # Показываем её размер, чтобы понимать, что теряем.
      if [ -d "$MODELS_DIR" ]; then
        SIZE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo "?")
        read -r -p "Удалить папку моделей '$MODELS_DIR' ($SIZE)? [y/N] " answer
        if [[ "''${answer,,}" == "y" ]]; then
          rm -rf "$MODELS_DIR"
          echo "Папка моделей удалена."
        else
          echo "Папка моделей сохранена."
        fi
      else
        echo "Папка моделей '$MODELS_DIR' не найдена — нечего удалять."
      fi

      if podman image exists "$IMAGE" 2>/dev/null; then
        read -r -p "Удалить образ '$IMAGE'? [y/N] " answer
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

  # --- Статус ---
  gufoStatus = pkgs.writeShellApplication {
    name = "gufo-status";
    runtimeInputs = [ pkgs.podman pkgs.coreutils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"
      IMAGE="${IMAGE}"
      MODELS_DIR="${MODELS_DIR}"

      echo "=== Модели ==="
      if [ -d "$MODELS_DIR" ]; then
        du -sh "$MODELS_DIR" 2>/dev/null || true
        echo
        find "$MODELS_DIR" -name "*.gguf" -type f -exec ls -lh {} \; 2>/dev/null | \
          awk '{print "  " $9 " (" $5 ")"}'
        echo
        INCOMPLETE=$(find "$MODELS_DIR" -name "*.incomplete" -type f 2>/dev/null | wc -l)
        if [ "$INCOMPLETE" -gt 0 ]; then
          echo "ВНИМАНИЕ: найдено $INCOMPLETE незавершённых загрузок:"
          find "$MODELS_DIR" -name "*.incomplete" -type f -exec ls -lh {} \; 2>/dev/null
        else
          echo "Незавершённых загрузок нет."
        fi
      else
        echo "Папка '$MODELS_DIR' не существует. Модели не скачаны."
      fi

      echo
      echo "=== Контейнер ==="
      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        if podman container running "$CONTAINER_NAME" 2>/dev/null; then
          echo "  '$CONTAINER_NAME' — запущен"
        else
          echo "  '$CONTAINER_NAME' — остановлен"
        fi
      else
        echo "  Контейнер '$CONTAINER_NAME' не создан"
      fi

      echo
      echo "=== Образ ==="
      if podman image exists "$IMAGE" 2>/dev/null; then
        SIZE=$(podman image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null | \
          awk '{printf "%.1f ГБ", $1/1024/1024/1024}')
        echo "  '$IMAGE' — есть локально ($SIZE)"
      else
        echo "  Образ '$IMAGE' не скачан"
      fi
    '';
  };

in
{
  home.packages = [
    gufoInstall
    gufoStart
    gufoStop
    gufoRemove
    gufoStatus
  ];

  xdg.desktopEntries = {
    gufo-start = {
      name = "Gufo Start";
      genericName = "Start Gufo inference server";
      exec = "gufo-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
