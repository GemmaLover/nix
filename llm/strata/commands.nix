{ config, pkgs, lib, strataConfig, ... }:

# Все константы — из strataConfig (см. default.nix).
# SC2034 не возникает: константы в bash-скриптах не объявляются,
# а подставляются интерполяцией.

let
  inherit (strataConfig)
    containerName imageName imageTag
    portHost portContainer
    strataDir dataDir ggufDir
    family modelSize contextTokens backend
    rocmVersion rocmUrl rocmSha256
    gpuArgs;

  containerfilePath = "${strataDir}/Containerfile";

in
{
  home.packages = [

    # =====================================================================
    # strata-image-build — собрать/пересобрать тонкий образ.
    # Нужно один раз и потом только при правках Containerfile
    # (например, при апдейте Ubuntu или добавлении зависимостей).
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-image-build";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail

        if [ ! -f "${containerfilePath}" ]; then
          echo "Containerfile не найден: ${containerfilePath}" >&2
          echo "Запусти n13rebuild — home-manager его создаст." >&2
          exit 1
        fi

        echo "=== Собираю образ ${imageName}:${imageTag} ==="
        podman build \
          -t "${imageName}:${imageTag}" \
          -f "${containerfilePath}" \
          "${strataDir}"

        echo "=== Готово ==="
        podman image inspect "${imageName}:${imageTag}" \
          --format 'Размер: {{.Size}} байт'
      '';
    })

    # =====================================================================
    # strata-setup — установка.
    #
    # Порядок:
    #   1. mkdir data/
    #   2. ROCm (если нет): curl + sha256 + tar → ~/llm/strata/rocm/install
    #   3. git clone Strata (если нет) → ~/llm/strata/src
    #   4. Образ (если нет) — через strata-image-build
    #   5. venv + pip install requirements.txt (в контейнере, ~2 мин)
    #   6. Движок: если build-halo/strata нет — собрать (25+ мин)
    #   7. engine/strata + engine/BUILD.json (source=local, backend=hip)
    #   8. python setup.py --setup --yes ... --no-start
    #      (скачивает MTP, строит pack из GGUF — 30-60 мин)
    #
    # Всё идемпотентно. Повторный запуск ничего не переделывает.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [
        pkgs.podman pkgs.git pkgs.curl pkgs.coreutils
        pkgs.gnutar pkgs.gnugrep
      ];
      text = ''
        # shellcheck disable=SC2016
        # SC2016 ложный: bash -lc '...' в конце скрипта намеренно в
        # одинарных кавычках — внутренний скрипт разворачивается
        # контейнерным bash, а не внешним.
        set -euo pipefail

        STRATA_DIR="${strataDir}"
        ROCM_DIR="$STRATA_DIR/rocm"
        ROCM_TGZ="$ROCM_DIR/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz"
        SDK="$ROCM_DIR/install"
        SRC="$STRATA_DIR/src"
        DATA_DIR="${dataDir}"
        GGUF_DIR="${ggufDir}"

        mkdir -p "$STRATA_DIR" "$ROCM_DIR" "$DATA_DIR" "$DATA_DIR/home"

        # === Информация о VPN ===
        if EXT_IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null); then
          echo "Внешний IP: $EXT_IP"
        else
          echo "Внешний IP не определён (сеть недоступна?). Продолжаю."
        fi
        echo

        # === Шаг 1: ROCm ===
        if [ ! -f "$ROCM_TGZ" ]; then
          echo "=== Скачиваю ROCm ${rocmVersion} (~1.7 ГБ) ==="
          curl -L --progress-bar -o "$ROCM_TGZ" "${rocmUrl}"
        else
          echo "=== ROCm уже скачан ==="
        fi

        echo "Проверяю sha256..."
        if ! echo "${rocmSha256}  $ROCM_TGZ" | sha256sum -c -; then
          echo "ОШИБКА: sha256 не совпал. Удали и запусти снова:" >&2
          echo "  rm '$ROCM_TGZ'" >&2
          exit 1
        fi

        if [ ! -x "$SDK/bin/hipcc" ]; then
          echo "=== Распаковываю ROCm в $SDK ==="
          mkdir -p "$SDK"
          tar -xzf "$ROCM_TGZ" -C "$SDK" --strip-components=1
        else
          echo "=== ROCm уже распакован ==="
        fi

        if [ ! -x "$SDK/bin/hipcc" ] || [ ! -e "$SDK/lib/libhipblas.so" ]; then
          echo "ОШИБКА: в $SDK нет hipcc или libhipblas.so —" >&2
          echo "setup.py не признает его системным ROCm." >&2
          exit 1
        fi

        # === Шаг 2: git clone ===
        if [ ! -d "$SRC/.git" ]; then
          echo "=== Клонирую Strata в $SRC ==="
          git clone https://github.com/Niko1221/Strata.git "$SRC"
        else
          echo "=== Исходники уже склонированы ==="
        fi

        # === Шаг 3: образ ===
        if ! podman image exists "${imageName}:${imageTag}" 2>/dev/null; then
          echo "=== Собираю образ ==="
          strata-image-build
        else
          echo "=== Образ уже есть ==="
        fi

        # === Шаги 4-6: venv, движок, BUILD.json, setup.py ===
        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Внутри контейнера:"
        echo "   1) venv + pip install requirements.txt (2 мин)"
        echo "   2) сборка движка при необходимости (~25 мин, если нет)"
        echo "   3) engine/BUILD.json (source=local, backend=hip, gfx1151)"
        echo "   4) python setup.py --setup --yes ..."
        echo "      (проверка SHA-256 GGUF + построение pack — 30-60 мин)"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        podman run --rm -it \
          ${gpuArgs} \
          -e STRATA_DATA=/data \
          -e HOME=/data/home \
          -e ROCM_PATH=/opt/rocm \
          -e HIP_PATH=/opt/rocm \
          -e HIP_PLATFORM=amd \
          -e LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib/rocm_sysdeps/lib:/opt/rocm/lib/llvm/lib \
          -v "$STRATA_DIR:/strata:Z" \
          -v "$SDK:/opt/rocm" \
          -v "$DATA_DIR:/data:Z" \
          -v "$GGUF_DIR:/gguf:Z" \
          -w /strata/src \
          "${imageName}:${imageTag}" \
          bash -lc '
            set -euo pipefail
            cd /strata/src

            # ── venv ────────────────────────────────────────────────
            if [ ! -x .venv/bin/python ]; then
              echo ">>> Создаю venv"
              python3 -m venv .venv
            fi
            if ! .venv/bin/python -c "import numpy" 2>/dev/null; then
              echo ">>> Ставлю requirements.txt"
              .venv/bin/pip install --no-cache-dir --upgrade pip
              .venv/bin/pip install --no-cache-dir -r requirements.txt
            else
              echo ">>> venv уже готов"
            fi

            # ── сборка движка (если нет) ───────────────────────────
            if [ ! -x build-halo/strata ]; then
              echo ">>> Собираю движок (25+ мин)"
              cmake -S . -B build-halo -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DSTRATA_ENABLE_HIP=ON \
                -DSTRATA_ENABLE_CUDA=OFF \
                -DSTRATA_PREFILL_MMQ=ON \
                -DCMAKE_HIP_ARCHITECTURES=gfx1151 \
                -DCMAKE_HIP_COMPILER=/opt/rocm/lib/llvm/bin/clang++ \
                -DCMAKE_HIP_COMPILER_ROCM_ROOT=/opt/rocm \
                "-DCMAKE_PREFIX_PATH=/opt/rocm;/opt/rocm/lib/rocm_sysdeps;/opt/rocm/lib/llvm" \
                "-DCMAKE_HIP_FLAGS=--rocm-path=/opt/rocm --rocm-device-lib-path=/opt/rocm/lib/llvm/amdgcn/bitcode"
              cmake --build build-halo --target strata -j "$(nproc)"
            else
              echo ">>> Движок уже собран: build-halo/strata"
            fi

            # ── engine/strata + BUILD.json ─────────────────────────
            # setup.py ищет бинарь в engine/strata и метаданные в
            # engine/BUILD.json. Если backend=hip, src совпадает
            # с source_hash(ENGINE_SOURCES) и archs=[1151] — он
            # НЕ пересобирает движок, а использует наш.
            echo ">>> Готовлю engine/strata + BUILD.json"
            .venv/bin/python - <<PYEOF
import json, pathlib, shutil, sys
sys.path.insert(0, "/strata/src")
import setup

eng = setup.ROOT / "engine"
eng.mkdir(exist_ok=True)
shutil.copy2(setup.ROOT / "build-halo" / setup.EXE, eng / setup.EXE)

meta = {
    "source":     "local",
    "version":    setup.source_version(),
    "archs":      [1151],
    "backend":    "hip",
    "src":        setup.source_hash(setup.ENGINE_SOURCES),
    "vision":     "none",
    "vision_src": None,
    "isa_floor":  "",
}
(eng / "BUILD.json").write_text(json.dumps(meta, indent=1))
print("  backend:", meta["backend"])
print("  src:    ", meta["src"])
print("  archs:  ", meta["archs"])
PYEOF

            # ── setup.py --setup ──────────────────────────────────
            echo ">>> python setup.py --setup --yes (долгая часть)"
            .venv/bin/python setup.py --setup --yes \
              --family "${family}" \
              --model  "${modelSize}" \
              --context "${toString contextTokens}" \
              --backend "${backend}" \
              --data-dir /data \
              --gguf-dir /gguf \
              --host 0.0.0.0 \
              --port ${toString portContainer} \
              --no-start

            echo ">>> Готово."
          '

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка завершена."
        echo "  Конфиг: $DATA_DIR/config/strata-${family}-$(echo '${modelSize}' | tr '[:upper:]' '[:lower:]').json"
        echo "  Запуск:  strata-start"
        echo "═══════════════════════════════════════════════════════════════"
      '';
    })

    # =====================================================================
    # strata-start — запуск сервера.
    # setup.py без --setup читает готовый конфиг и поднимает
    # serve/server.py, который сам спавнит strata --serve.
    # Сервер слушает 0.0.0.0:PORT, конфиг уже содержит host/port.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.coreutils ];
      text = ''
        set -euo pipefail

        STRATA_DIR="${strataDir}"
        ROCM_DIR="$STRATA_DIR/rocm"
        SDK="$ROCM_DIR/install"
        DATA_DIR="${dataDir}"
        GGUF_DIR="${ggufDir}"
        PORT_HOST=${toString portHost}

        if [ ! -x "$STRATA_DIR/src/engine/strata" ]; then
          echo "Движок не установлен. Сначала: strata-setup" >&2
          exit 1
        fi

        CFG="$DATA_DIR/config/strata-${family}-$(echo '${modelSize}' | tr '[:upper:]' '[:lower:]').json"
        if [ ! -f "$CFG" ]; then
          echo "Конфиг не найден: $CFG" >&2
          echo "Сначала: strata-setup" >&2
          exit 1
        fi

        podman rm -f "${containerName}" 2>/dev/null || true

        echo "=== Запуск ${containerName} (порт $PORT_HOST) ==="

        podman run -d --name "${containerName}" \
          ${gpuArgs} \
          -p "$PORT_HOST:${toString portContainer}" \
          -e STRATA_DATA=/data \
          -e HOME=/data/home \
          -e ROCM_PATH=/opt/rocm \
          -e HIP_PATH=/opt/rocm \
          -e HIP_PLATFORM=amd \
          -e LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib/rocm_sysdeps/lib:/opt/rocm/lib/llvm/lib \
          -e STRATA_HIPBLASLT_TUNING=/strata/src/tools/hip/gfx1151-hipblaslt-100401.txt \
          -v "$STRATA_DIR:/strata:Z" \
          -v "$SDK:/opt/rocm" \
          -v "$DATA_DIR:/data:Z" \
          -v "$GGUF_DIR:/gguf:Z" \
          -w /strata/src \
          "${imageName}:${imageTag}" \
          /strata/src/.venv/bin/python /strata/src/setup.py \
            --port ${toString portContainer} \
            "$@"

        # Проверка что контейнер не упал сразу.
        sleep 5
        STATUS=$(podman inspect "${containerName}" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$STATUS" != "running" ]; then
          echo "Контейнер упал (статус: $STATUS). Логи:" >&2
          podman logs "${containerName}" 2>&1 | tail -60 >&2 || true
          exit 1
        fi

        URL="http://localhost:$PORT_HOST"
        echo "=== Запущено. Логи: strata-logs ==="
        echo "=== URL:  $URL ==="
        echo "=== Модель грузится 1-3 минуты; страница откроется, когда сервер ответит ==="

        # Ждём HTTP-ответа и открываем браузер.
        (
          for _ in $(seq 1 600); do
            if curl -fsS -o /dev/null "$URL/health" 2>/dev/null \
              || curl -fsS -o /dev/null "$URL/" 2>/dev/null; then
              ${pkgs.xdg-utils}/bin/xdg-open "$URL" >/dev/null 2>&1 || true
              exit 0
            fi
            sleep 2
          done
        ) &
      '';
    })

    # =====================================================================
    # strata-stop — мягкая остановка.
    # Движок держит десятки ГБ page-locked RAM, поэтому SIGTERM
    # может занять до 30-60 с. Даём 60, потом kill.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-stop";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        if ! podman container exists "${containerName}" 2>/dev/null; then
          echo "Контейнер ${containerName} не найден."
          exit 0
        fi

        STATUS=$(podman inspect "${containerName}" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю ${containerName} (SIGTERM, до 60 с)..."
            podman stop -t 60 "${containerName}" 2>/dev/null || {
              echo "SIGTERM не сработал, kill..."
              podman kill "${containerName}" 2>/dev/null || true
            }
            ;;
          *)
            echo "Уже остановлен (статус: $STATUS)."
            ;;
        esac
        podman rm -f "${containerName}" 2>/dev/null || true
        echo "Готово."
      '';
    })

    # =====================================================================
    # strata-logs — смотреть лог сервера.
    # Что искать в логе:
    #   - «backend: hip» или «HIP» — движок на AMD.
    #   - «prefill gemm: hipBLASLt tuning enabled» — таблица подхвачена.
    #   - строку про expert-cache (auto или число).
    #   - «listening on» или финальный URL.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-logs";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        exec podman logs -f "${containerName}" "$@"
      '';
    })

    # =====================================================================
    # strata-shell — интерактивный bash внутри образа.
    # Для отладки: проверить clinfo/rocminfo, потрогать setup.py,
    # запустить serve вручную.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-shell";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        STRATA_DIR="${strataDir}"
        ROCM_DIR="$STRATA_DIR/rocm"
        SDK="$ROCM_DIR/install"

        exec podman run --rm -it \
          ${gpuArgs} \
          -e STRATA_DATA=/data \
          -e HOME=/data/home \
          -e ROCM_PATH=/opt/rocm \
          -e HIP_PATH=/opt/rocm \
          -e HIP_PLATFORM=amd \
          -e LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib/rocm_sysdeps/lib:/opt/rocm/lib/llvm/lib \
          -v "$STRATA_DIR:/strata:Z" \
          -v "$SDK:/opt/rocm" \
          -v "${dataDir}:/data:Z" \
          -v "${ggufDir}:/gguf:Z" \
          --entrypoint /bin/bash \
          "${imageName}:${imageTag}"
      '';
    })

    # =====================================================================
    # strata-update — git pull + пересборка движка + пересборка pack.
    # Pack НЕ пересобирается (setup.py видит уже готовый).
    # Если нужен новый ROCm — обнови rocmUrl/rocmSha256 в default.nix,
    # удали ~/llm/strata/rocm/therock-*.tar.gz и rocm/install/,
    # потом запусти strata-setup заново.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail
        SRC="${strataDir}/src"

        if [ ! -d "$SRC/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "=== git pull ==="
        git -C "$SRC" pull --ff-only

        echo "=== Сбрасываю build-halo и engine ==="
        rm -rf "$SRC/build-halo" "$SRC/engine"

        echo "=== Пересборка через strata-setup ==="
        exec strata-setup
      '';
    })

    # =====================================================================
    # strata-remove — снести контейнер, образ, src, rocm, data.
    # Спрашивает подтверждения на каждый пункт.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        IMAGE="${imageName}:${imageTag}"
        STRATA_DIR="${strataDir}"
        DATA_DIR="${dataDir}"

        podman rm -f "${containerName}" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ $IMAGE? [y/N] " answer
          case "$answer" in
            y|Y) podman rmi "$IMAGE"; echo "Образ удалён." ;;
            *)   echo "Образ сохранён." ;;
          esac
        fi

        if [ -d "$STRATA_DIR/src" ]; then
          SIZE=$(du -sh "$STRATA_DIR/src" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $STRATA_DIR/src ($SIZE)? [y/N] " answer
          case "$answer" in
            y|Y) rm -rf "$STRATA_DIR/src"; echo "src удалён." ;;
            *)   echo "src сохранён." ;;
          esac
        fi

        if [ -d "$STRATA_DIR/rocm" ]; then
          SIZE=$(du -sh "$STRATA_DIR/rocm" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $STRATA_DIR/rocm ($SIZE)? [y/N] " answer
          case "$answer" in
            y|Y) rm -rf "$STRATA_DIR/rocm"; echo "rocm удалён." ;;
            *)   echo "rocm сохранён." ;;
          esac
        fi

        if [ -d "$DATA_DIR" ]; then
          SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $DATA_DIR ($SIZE — pack + конфиг + MTP)? [y/N] " answer
          case "$answer" in
            y|Y) rm -rf "$DATA_DIR"; echo "data удалён." ;;
            *)   echo "data сохранён." ;;
          esac
        fi

        echo "Готово."
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
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
    strata-logs = {
      name = "Strata Logs";
      exec = "strata-logs";
      icon = "utilities-terminal";
      terminal = true;
      categories = [ "Development" "Science" ];
    };
  };
}
