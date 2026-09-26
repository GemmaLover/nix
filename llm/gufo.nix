{ config, pkgs, ... }:

let
  # =====================================================================
  # Gufo — движок инференса для AMD Strix Halo (gfx1151).
  #
  # ВАЖНО:
  #   - Gufo — OpenAI-совместимый сервер, но БЕЗ /health.
  #     Проверка готовности — через /v1/models.
  #   - Все запросы использовать с --ipv4 и 127.0.0.1, потому что
  #     passt (Podman rootless network) глючит с IPv6.
  #   - API-ключ передаётся через --api-key.
  #
  # API Base URL для DSH/Open WebUI:  http://127.0.0.1:8887/v1
  # =====================================================================

  CONTAINER_NAME = "gufo-qwen27b";
  IMAGE = "ghcr.io/gufo-org/toolboxes/gufo-runtime:latest";
  MODELS_DIR = "\${HOME}/llm/models/gufo";
  PORT_HOST = 8887;
  PORT_CONTAINER = 8080;
  API_KEY = "24g2rgrg24rc234cg23cg2g2tgctb249nibtbn20tbi";

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
      API_KEY="${API_KEY}"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' уже существует."
        echo "Для пересоздания запустите gufo-remove."
        exit 1
      fi

      echo "=== Скачивание моделей ==="
      mkdir -p "$MODELS_DIR"

      MODEL_MAIN="$MODELS_DIR/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K_XL.gguf"
      if [ -f "$MODEL_MAIN" ] && [ ! -f "$MODEL_MAIN.incomplete" ]; then
        SIZE=$(du -h "$MODEL_MAIN" | cut -f1)
        echo "Модель Qwen3.8-27B уже скачана ($SIZE)."
      else
        if [ -f "$MODEL_MAIN.incomplete" ]; then
          echo "Найден незавершённый файл — докачиваю."
        else
          echo "Скачиваю Qwen3.8-27B-UD-Q6_K_XL.gguf (~24 ГБ)..."
        fi
        hf download unsloth/Qwen3.8-27B-GGUF \
          Qwen3.8-27B-UD-Q6_K_XL.gguf \
          --revision 4ca720788d1e01f1bff70c033e0d0028fd02e502 \
          --repo-type model \
          --local-dir "$MODELS_DIR/Qwen3.8-27B-GGUF"
      fi

      MODEL_DRAFT="$MODELS_DIR/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
      if [ -f "$MODEL_DRAFT" ] && [ ! -f "$MODEL_DRAFT.incomplete" ]; then
        SIZE=$(du -h "$MODEL_DRAFT" | cut -f1)
        echo "DFlash2 драфтер уже скачан ($SIZE)."
      else
        if [ -f "$MODEL_DRAFT.incomplete" ]; then
          echo "Найден незавершённый файл — докачиваю."
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
          --api-key "$API_KEY" \
          --model /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q6_K_XL.gguf \
          --speculative dflash2 \
          --dflash-model /models/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf

      echo
      echo "Контейнер '$CONTAINER_NAME' создан."
      echo "API Base URL:  http://127.0.0.1:$PORT_HOST/v1"
      echo "API Key:       $API_KEY"
      echo "Запуск:        gufo-start"
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
      # Используем 127.0.0.1, потому что passt (Podman network) ломается на IPv6.
      API_BASE="http://127.0.0.1:$PORT_HOST/v1"
      API_KEY="${API_KEY}"

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

      echo -n "Ожидание загрузки модели (это долго, до 2 минут)"
      READY=0
      for _ in {1..180}; do
        # --ipv4 обязательно: passt ломается на IPv6.
        # Используем /v1/models — это единственный «health»-эндпоинт.
        if curl --ipv4 -fsS -o /dev/null \
             -H "Authorization: Bearer $API_KEY" \
             "$API_BASE/models" 2>/dev/null; then
          echo " — готов."
          READY=1
          break
        fi
        echo -n "."
        sleep 1
      done

      if [ "$READY" -eq 0 ]; then
        echo " — не дождались. Проверьте логи:"
        echo "  podman logs --tail 50 $CONTAINER_NAME"
        exit 1
      fi

      echo
      echo "=================================================="
      echo "  Gufo готов"
      echo "=================================================="
      echo "  API Base URL:  $API_BASE"
      echo "  API Key:       $API_KEY"
      echo "  Модели:        $API_BASE/models"
      echo
      echo "  ВАЖНО: используйте 127.0.0.1, не localhost"
      echo "  (passt ломается на IPv6-запросах)."
      echo "=================================================="
      echo

      xdg-open "http://127.0.0.1:$PORT_HOST/v1/models" &
    '';
  };

  # --- Остановка ---
  gufoStop = pkgs.writeShellApplication {
    name = "gufo-stop";
    runtimeInputs = [ pkgs.podman pkgs.procps ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="${CONTAINER_NAME}"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер '$CONTAINER_NAME' не найден."
        exit 0
      fi

      if ! podman container running "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже остановлен."
        exit 0
      fi

      echo "Останавливаю контейнер (таймаут 30 секунд)..."
      podman stop -t 30 "$CONTAINER_NAME" || {
        echo "Контейнер не остановился штатно, убиваю принудительно..."
        podman kill "$CONTAINER_NAME" 2>/dev/null || true
        podman wait "$CONTAINER_NAME" 2>/dev/null || true
      }
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
        find "$MODELS_DIR" -name "*.gguf" -type f -exec ls -lh {} \; 2>/dev/null | \
          awk '{print "  " $9 " (" $5 ")"}'
        INCOMPLETE=$(find "$MODELS_DIR" -name "*.incomplete" -type f 2>/dev/null | wc -l)
        if [ "$INCOMPLETE" -gt 0 ]; then
          echo "ВНИМАНИЕ: найдено $INCOMPLETE незавершённых загрузок."
        fi
      else
        echo "Папка '$MODELS_DIR' не существует."
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
