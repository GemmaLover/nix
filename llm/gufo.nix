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

      # Qwen3.8-27B (основная модель, Q6_K_XL)
      if [ ! -f "$MODELS_DIR/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K_XL.gguf" ]; then
        echo "Скачиваю Qwen3.8-27B-UD-Q6_K_XL.gguf (~24 ГБ)..."
        hf download unsloth/Qwen3.8-27B-GGUF \
          Qwen3.8-27B-UD-Q6_K_XL.gguf \
          --revision 4ca720788d1e01f1bff70c033e0d0028fd02e502 \
          --repo-type model \
          --local-dir "$MODELS_DIR/Qwen3.8-27B-GGUF"
      else
        echo "Модель Qwen3.8-27B уже скачана."
      fi

      # DFlash2 драфтер (Q4_K_M)
      if [ ! -f "$MODELS_DIR/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf" ]; then
        echo "Скачиваю DFlash2 драфтер (~4 ГБ)..."
        hf download z-lab/Qwen3.8-27B-DFlash2-GGUF \
          Qwen3.8-27B-DFlash2-Q4_K_M.gguf \
          --revision 2d9571f8ce46e151f61c6499c99dee6079e1d610 \
          --repo-type model \
          --local-dir "$MODELS_DIR/Qwen3.8-27B-DFlash2-GGUF"
      else
        echo "DFlash2 драфтер уже скачан."
      fi

      echo
      echo "=== Создание Podman-контейнера ==="
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

in
{
  home.packages = [
    gufoInstall
    gufoStart
    gufoStop
    gufoRemove
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
