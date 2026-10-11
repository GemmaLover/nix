{ config, pkgs, lib, strataConfig, ... }:

# Все константы — из strataConfig (см. default.nix).
# В bash-скриптах путей и портов в хардкоде нет: всё через интерполяцию.
# SC2034 (unused vars IMAGE/PORT_HOST/PORT_CONTAINER) убран: эти значения
# стали Nix-константами и попадают в скрипты как строковые литералы.

let
  inherit (strataConfig)
    containerName imageName imageTag
    portHost portContainer
    strataDir modelsDir modelFile
    rocmVersion rocmUrl rocmSha256
    hipblasltTuning expertCache
    gpuArgs fastEnvArgs;

  # Куда home-manager положил Containerfile (см. default.nix).
  containerfilePath = "${strataDir}/Containerfile";

in
{
  home.packages = [

    # =====================================================================
    # strata-image-build — собрать/пересобрать тонкий образ.
    #
    # Запускать один раз при первой установке и повторно — после правок
    # Containerfile (например, при апдейте тулчейна). Обычно это не нужно:
    # ROCm живёт на хосте, а не в образе.
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
        # Контекст — сам каталог strataDir. Там лежит Containerfile.
        # README.md в контексте нет — сборка чистая.
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
    # strata-setup — одноразовая установка и сборка.
    #
    # Порядок:
    #   1. Каталоги на хосте (~/llm/strata, ~/llm/strata/rocm).
    #   2. Скачать TheRock ROCm 7.14.1 (~1.7 ГБ) с repo.amd.com.
    #      Если активен waydroid-vpn-connect — идёт через VPN автоматически.
    #      Отдельные прокси-переменные НЕ нужны (см. комментарий внизу).
    #   3. Проверить sha256.
    #   4. Распаковать в ~/llm/strata/rocm/install.
    #   5. git clone Strata в ~/llm/strata/src (если ещё нет).
    #   6. Собрать образ (если ещё нет).
    #   7. Собрать движок в контейнере. ~25 минут в первый раз.
    #
    # Идемпотентно: повторный запуск не качает и не пересобирает то,
    # что уже готово. Для принудительной пересборки движка — strata-update.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [
        pkgs.podman pkgs.git pkgs.curl pkgs.coreutils
        pkgs.gnutar pkgs.gnugrep
      ];
      text = ''
        set -euo pipefail

        STRATA_DIR="${strataDir}"
        ROCM_DIR="$STRATA_DIR/rocm"
        ROCM_TGZ="$ROCM_DIR/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz"
        SDK="$ROCM_DIR/install"
        SRC="$STRATA_DIR/src"

        mkdir -p "$STRATA_DIR" "$ROCM_DIR"

        # === Информация о VPN ===
        # Когда selector = waydroid-out (команда waydroid-vpn-connect),
        # весь трафик хоста, включая curl и podman pull, уже идёт через
        # SOCKS5 внутрь Waydroid. Отдельные http_proxy/https_proxy НЕ
        # выставляем — они создадут петлю (curl → sing-box → selector →
        # waydroid-out → SOCKS5 внутри Android → VPN).
        if EXT_IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null); then
          echo "Внешний IP: $EXT_IP"
          echo "(если это IP VPN — скачивание и сборка идут через VPN)"
        else
          echo "Внешний IP не определён (сеть недоступна?). Продолжаю."
        fi
        echo

        # === Шаг 1: ROCm SDK ===
        if [ ! -f "$ROCM_TGZ" ]; then
          echo "=== Скачиваю ROCm ${rocmVersion} (~1.7 ГБ) ==="
          echo "URL: ${rocmUrl}"
          curl -L --progress-bar -o "$ROCM_TGZ" "${rocmUrl}"
        else
          echo "=== ROCm уже скачан: $ROCM_TGZ ==="
        fi

        # === Шаг 2: sha256 ===
        echo "Проверяю sha256..."
        if ! echo "${rocmSha256}  $ROCM_TGZ" | sha256sum -c -; then
          echo "ОШИБКА: sha256 не совпал. Файл скачался битым." >&2
          echo "Удали и запусти снова:" >&2
          echo "  rm '$ROCM_TGZ'" >&2
          exit 1
        fi

        # === Шаг 3: распаковка ===
        # Индикатор — наличие clang++ (главного бинаря, который используем).
        if [ ! -x "$SDK/lib/llvm/bin/clang++" ]; then
          echo "=== Распаковываю ROCm в $SDK ==="
          mkdir -p "$SDK"
          # TheRock-тарбол содержит один верхнеуровневый каталог — срезаем.
          tar -xzf "$ROCM_TGZ" -C "$SDK" --strip-components=1
        else
          echo "=== ROCm уже распакован: $SDK ==="
        fi

        if [ ! -x "$SDK/lib/llvm/bin/clang++" ]; then
          echo "ОШИБКА: $SDK/lib/llvm/bin/clang++ не найден." >&2
          echo "Проверь содержимое: ls '$SDK/lib/llvm/bin/' | head" >&2
          exit 1
        fi

        # === Шаг 4: git clone ===
        if [ ! -d "$SRC/.git" ]; then
          echo "=== Клонирую Strata в $SRC ==="
          git clone https://github.com/Niko1221/Strata.git "$SRC"
        else
          echo "=== Исходники уже склонированы: $SRC ==="
        fi

        # === Шаг 5: образ ===
        if ! podman image exists "${imageName}:${imageTag}" 2>/dev/null; then
          echo "=== Собираю образ ${imageName}:${imageTag} ==="
          podman build \
            -t "${imageName}:${imageTag}" \
            -f "${containerfilePath}" \
            "$STRATA_DIR"
        else
          echo "=== Образ уже есть: ${imageName}:${imageTag} ==="
        fi

        # === Шаг 6: сборка движка ===
        if [ -x "$SRC/build-halo/strata" ]; then
          echo "=== Движок уже собран: $SRC/build-halo/strata ==="
          echo "Для пересборки: strata-update (git pull + rm build-halo + setup)"
          exit 0
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Сборка Strata (25+ минут, зависит от CPU)."
        echo "  SDK:        $SDK"
        echo "  Исходники:  $SRC"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        # Внутри контейнера SDK смонтирован как /strata/rocm/install —
        # пути в cmake-флагах контейнерные, не хостовые.
        # --it нужен для прогресс-бара ninja. Если нет TTY — убери -t,
        # cmake всё равно соберёт.
        podman run --rm -it \
          ${gpuArgs} \
          -v "$STRATA_DIR:/strata:Z" \
          -w /strata/src \
          "${imageName}:${imageTag}" \
          bash -lc '
            set -euo pipefail

            SDK=/strata/rocm/install
            export ROCM_PATH=$SDK
            export HIP_PATH=$SDK
            export HIP_PLATFORM=amd
            export PATH="$SDK/bin:$SDK/lib/llvm/bin:$PATH"
            export LD_LIBRARY_PATH="$SDK/lib:$SDK/lib/rocm_sysdeps/lib:$SDK/lib/llvm/lib:''${LD_LIBRARY_PATH:-}"

            echo "=== Версия clang ==="
            "$SDK/lib/llvm/bin/clang++" --version | head -3

            echo "=== CMake конфигурация ==="
            # Флаги из docs/STRIX_HALO.md (раздел 2 «The engine»).
            # --gcc-toolchain НЕ нужен: у нас есть системный gcc из apt.
            cmake -S . -B build-halo -G Ninja \
              -DCMAKE_BUILD_TYPE=Release \
              -DSTRATA_ENABLE_HIP=ON \
              -DSTRATA_ENABLE_CUDA=OFF \
              -DSTRATA_PREFILL_MMQ=ON \
              -DCMAKE_HIP_ARCHITECTURES=gfx1151 \
              -DCMAKE_HIP_COMPILER="$SDK/lib/llvm/bin/clang++" \
              -DCMAKE_HIP_COMPILER_ROCM_ROOT="$SDK" \
              "-DCMAKE_PREFIX_PATH=$SDK;$SDK/lib/rocm_sysdeps;$SDK/lib/llvm" \
              "-DCMAKE_HIP_FLAGS=--rocm-path=$SDK --rocm-device-lib-path=$SDK/lib/llvm/amdgcn/bitcode"

            echo "=== Сборка target strata ==="
            cmake --build build-halo --target strata -j "$(nproc)"
          '

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка завершена."
        echo "  Движок: $SRC/build-halo/strata"
        echo "  Запуск:  strata-start"
        echo "═══════════════════════════════════════════════════════════════"
      '';
    })

    # =====================================================================
    # strata-start — запуск сервера в фоне.
    #
    # Передаёт движку:
    #   -m /models/<modelFile>   — модель (multi-part GGUF: первый файл)
    #   --serve --host 0.0.0.0 --port <portContainer>
    #   --expert-cache <N>       — иначе auto может уйти в OOM (#1715)
    #
    # Модель монтируется read-only из modelsDir (см. default.nix).
    # Исходники и ROCm — read-write, потому что движок может писать
    # кэш в каталог сборки.
    #
    # Дополнительные аргументы можно передать вручную:
    #   strata-start -- --spec 4 --mtp
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="${containerName}"
        STRATA_DIR="${strataDir}"
        MODELS_DIR="${modelsDir}"
        MODEL_FILE="${modelFile}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        BIN="$STRATA_DIR/src/build-halo/strata"
        MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

        if [ ! -x "$BIN" ]; then
          echo "Движок не собран: $BIN" >&2
          echo "Сначала: strata-setup" >&2
          exit 1
        fi

        if [ ! -f "$MODEL_PATH" ]; then
          echo "Модель не найдена: $MODEL_PATH" >&2
          echo "Проверь modelFile в llm/strata/default.nix." >&2
          exit 1
        fi

        # Пересоздаём контейнер каждый раз — так проще менять env
        # и не ловить stale-конфиг.
        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        echo "=== Запуск $CONTAINER_NAME (порт $PORT_HOST) ==="

        # Монтирования:
        #   $STRATA_DIR     → /strata     (rw: бинарь + ROCm + кэш)
        #   $MODELS_DIR     → /models     (ro: модели)
        #
        # LD_LIBRARY_PATH: сначала ROCm, потом sysdeps (zlib, elfutils),
        # потом LLVM/AMDGPU. Порядок важен.
        #
        # STRATA_HIPBLASLT_TUNING — таблица автотюнинга hipBLASLt для
        # gfx1151, лежит в самом репозитории.
        #
        # env из fastEnvArgs — быстрый профиль (см. default.nix).
        podman run -d --name "$CONTAINER_NAME" \
          ${gpuArgs} \
          -p "$PORT_HOST:$PORT_CONTAINER" \
          -v "$STRATA_DIR:/strata:Z" \
          -v "$MODELS_DIR:/models:ro" \
          -e ROCM_PATH=/strata/rocm/install \
          -e HIP_PATH=/strata/rocm/install \
          -e HIP_PLATFORM=amd \
          -e LD_LIBRARY_PATH=/strata/rocm/install/lib:/strata/rocm/install/lib/rocm_sysdeps/lib:/strata/rocm/install/lib/llvm/lib \
          -e STRATA_HIPBLASLT_TUNING="/strata/src/${hipblasltTuning}" \
          ${fastEnvArgs} \
          "${imageName}:${imageTag}" \
          /strata/src/build-halo/strata serve \
            -m "/models/$MODEL_FILE" \
            --host 0.0.0.0 \
            --port "$PORT_CONTAINER" \
            --expert-cache ${toString expertCache} \
            "$@"

        # Короткая пауза и проверка, что контейнер не упал на старте.
        sleep 3
        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$STATUS" != "running" ]; then
          echo "Контейнер упал (статус: $STATUS). Логи:" >&2
          podman logs "$CONTAINER_NAME" 2>&1 | tail -40 >&2 || true
          exit 1
        fi

        URL="http://localhost:$PORT_HOST"
        echo "=== Запущено. Логи: strata-logs ==="
        echo "=== URL:  $URL ==="
        xdg-open "$URL" >/dev/null 2>&1 &
      '';
    })

    # =====================================================================
    # strata-stop — мягкая остановка.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-stop";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="${containerName}"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Контейнер $CONTAINER_NAME не найден."
          exit 0
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю $CONTAINER_NAME..."
            podman stop -t 30 "$CONTAINER_NAME" 2>/dev/null || {
              echo "SIGTERM не сработал, kill..."
              podman kill "$CONTAINER_NAME" 2>/dev/null || true
            }
            ;;
          *)
            echo "Уже остановлен (статус: $STATUS)."
            ;;
        esac
        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
        echo "Готово."
      '';
    })

    # =====================================================================
    # strata-logs — смотреть лог сервера.
    # В логе ищи две строки:
    #   - "prefill gemm: hipBLASLt tuning enabled (90 rows, gfx1151, version 100401)"
    #     → таблица подхватилась.
    #   - "gfx1151" в отчёте о дефолтах → движок узнал архитектуру.
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
    # Для отладки: проверить clinfo/rocminfo, потрогать бинарь, посмотреть
    # переменные окружения.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-shell";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        STRATA_DIR="${strataDir}"
        MODELS_DIR="${modelsDir}"

        exec podman run --rm -it \
          ${gpuArgs} \
          -v "$STRATA_DIR:/strata:Z" \
          -v "$MODELS_DIR:/models:ro" \
          -e ROCM_PATH=/strata/rocm/install \
          -e HIP_PATH=/strata/rocm/install \
          -e HIP_PLATFORM=amd \
          -e LD_LIBRARY_PATH=/strata/rocm/install/lib:/strata/rocm/install/lib/rocm_sysdeps/lib:/strata/rocm/install/lib/llvm/lib \
          -e STRATA_HIPBLASLT_TUNING="/strata/src/${hipblasltTuning}" \
          --entrypoint /bin/bash \
          "${imageName}:${imageTag}"
      '';
    })

    # =====================================================================
    # strata-update — git pull + пересборка движка.
    # ROCm не трогаем: если нужен новый ROCm, обнови rocmUrl/rocmSha256
    # в default.nix, удали ~/llm/strata/rocm/therock-*.tar.gz и
    # ~/llm/strata/rocm/install, потом запусти strata-setup.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        STRATA_DIR="${strataDir}"
        SRC="$STRATA_DIR/src"

        if [ ! -d "$SRC/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "=== git pull ==="
        git -C "$SRC" pull --ff-only

        echo "=== Удаляю build-halo для пересборки ==="
        rm -rf "$SRC/build-halo"

        echo "=== Пересборка через strata-setup ==="
        # strata-setup идемпотентен: ROCm и образ уже на месте, скачает
        # только то, чего нет, и пересоберёт движок.
        exec strata-setup
      '';
    })

    # =====================================================================
    # strata-remove — снести контейнер, образ, ROCm и исходники.
    # Спрашивает подтверждения на каждый пункт.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="${containerName}"
        IMAGE="${imageName}:${imageTag}"
        STRATA_DIR="${strataDir}"

        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ $IMAGE? [y/N] " answer
          case "$answer" in
            y|Y) podman rmi "$IMAGE"; echo "Образ удалён." ;;
            *)   echo "Образ сохранён." ;;
          esac
        fi

        if [ -d "$STRATA_DIR" ]; then
          SIZE=$(du -sh "$STRATA_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $STRATA_DIR ($SIZE — src + ROCm + build)? [y/N] " answer
          case "$answer" in
            y|Y) rm -rf "$STRATA_DIR"; echo "$STRATA_DIR удалён." ;;
            *)   echo "$STRATA_DIR сохранён." ;;
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
