{ config, pkgs, lib, strataConfig, ... }:

let
  inherit (strataConfig) image portHost portContainer strataDir
          rocmVersion rocmUrl rocmSha256 hipblasltTuning;
in
{
  home.packages = [
    # =====================================================================
    # Установка Strata (одноразовая).
    #
    # Порядок:
    #   1. Скачать ROCm SDK 7.14.1 для gfx1151 на хосте (curl через
    #      системный VPN — когда selector = waydroid-out, весь трафик
    #      хоста идёт через SOCKS5 Waydroid).
    #   2. Проверить sha256 (если не сходится — файл скачался битым,
    #      удалить и повторить).
    #   3. Распаковать в ~/llm/strata/rocm/install/.
    #   4. git clone Strata (если ещё нет).
    #   5. Собрать движок в контейнере Fedora:
    #      - dnf5 install cmake ninja-build gcc-c++
    #      - cmake с флагами из STRIX_HALO.md
    #      - cmake --build --target strata
    #
    # ПОДВОДНЫЕ КАМНИ:
    #   - Прокси-переменные НЕ нужны: когда активен waydroid-vpn-connect,
    #     весь трафик хоста (curl, git, podman pull) уже идёт через VPN
    #     автоматически. Прокси создаст петлю (curl → sing-box → selector
    #     → waydroid-out → SOCKS5 внутри Android → VPN).
    #   - На хосте (NixOS) clang из therock-dist НЕ запустится
    #     (динамически слинкован под FHS). Поэтому сборка в контейнере.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [
        pkgs.podman pkgs.git pkgs.curl pkgs.coreutils
      ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        ROCM_DIR="$STRATA_DIR/rocm"
        ROCM_TGZ="$ROCM_DIR/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz"
        SDK="$ROCM_DIR/install"

        mkdir -p "$STRATA_DIR" "$ROCM_DIR"

        # === Информация о текущем VPN-режиме ===
        # При waydroid-vpn-connect весь трафик хоста (включая curl и
        # podman pull) идёт через VPN. Отдельные прокси-переменные
        # НЕ НУЖНЫ — они создадут петлю (curl → sing-box → selector →
        # waydroid-out → SOCKS5 внутри Android → VPN).
        if curl -fsS --max-time 5 https://ifconfig.me >/dev/null 2>&1; then
          CURRENT_IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo "?")
          echo "Внешний IP: $CURRENT_IP"
          echo "(если это IP VPN — скачивание пойдёт через VPN автоматически)"
        fi
        echo

        # === Шаг 1: скачать ROCm SDK ===
        if [ ! -f "$ROCM_TGZ" ]; then
          echo "=== Скачиваю ROCm ${rocmVersion} (~1.7 ГБ) ==="
          echo "URL: ${rocmUrl}"
          curl -L --progress-bar -o "$ROCM_TGZ" "${rocmUrl}"
        else
          echo "=== ROCm уже скачан: $ROCM_TGZ ==="
        fi

        # === Шаг 2: проверить sha256 ===
        echo "Проверяю sha256..."
        if ! echo "${rocmSha256}  $ROCM_TGZ" | sha256sum -c -; then
          echo "ОШИБКА: неверный sha256 ROCm." >&2
          echo "Файл скачался битым. Удалите и запустите снова:" >&2
          echo "  rm $ROCM_TGZ" >&2
          exit 1
        fi

        # === Шаг 3: распаковать ===
        if [ ! -d "$SDK/lib/llvm" ]; then
          echo "=== Распаковываю ROCm в $SDK ==="
          mkdir -p "$SDK"
          tar -xzf "$ROCM_TGZ" -C "$SDK"
        else
          echo "=== ROCm уже распакован: $SDK ==="
        fi

        if [ ! -x "$SDK/lib/llvm/bin/clang++" ]; then
          echo "ОШИБКА: $SDK/lib/llvm/bin/clang++ не найден." >&2
          echo "Проверьте содержимое: ls $SDK/lib/llvm/bin/" >&2
          exit 1
        fi

        # === Шаг 4: клонировать Strata ===
        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "=== Клонирую Strata ==="
          git clone https://github.com/Niko1221/Strata.git "$STRATA_DIR"
        else
          echo "=== Обновляю исходники (git pull) ==="
          git -C "$STRATA_DIR" pull --ff-only || echo "  (git pull пропущен)"
        fi

        cd "$STRATA_DIR"

        if [ ! -f "CMakeLists.txt" ]; then
          echo "ОШИБКА: в $STRATA_DIR нет CMakeLists.txt — это не репозиторий Strata." >&2
          exit 1
        fi

        # === Шаг 5: сборка движка в контейнере Fedora ===
        # На хосте clang из therock-dist не запустится (NixOS), поэтому
        # собираем в контейнере kyuz0 — Fedora 44 с полным ROCm runtime.
        # Внутри ставим cmake+ninja+gcc-c++ (сам clang берётся из SDK).
        if [ -f "build-halo/strata" ]; then
          echo "=== Движок уже собран: build-halo/strata ==="
          echo "Для пересборки удалите build-halo/ и запустите снова."
          echo
          echo "Запуск сервера: strata-start"
          exit 0
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Сборка Strata (может занять 25+ минут)."
        echo "  SDK:    $SDK"
        echo "  Исходники: $STRATA_DIR"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        # Если образ не скачан — pull.
        # Он идёт через системный VPN автоматически (правила sing-box
        # завернули дефолт-роут в TUN, NAT контейнера тоже идёт через
        # этот роут). Отдельных прокси-переменных НЕ нужно.
        if ! podman image exists "$IMAGE" 2>/dev/null; then
          echo "=== Скачиваю образ $IMAGE ==="
          podman pull "$IMAGE"
        fi

        # Сборка в контейнере.
        #
        # Монтирования:
        #   $STRATA_DIR → /opt/Strata (исходники + SDK + билд)
        #
        # Флаги cmake — из docs/STRIX_HALO.md:
        #   -DSTRATA_ENABLE_HIP=ON         — включить HIP/ROCm
        #   -DSTRATA_ENABLE_CUDA=OFF       — выключить CUDA
        #   -DSTRATA_PREFILL_MMQ=ON        — ускоренный prefill
        #   -DCMAKE_HIP_ARCHITECTURES=gfx1151
        #   -DCMAKE_HIP_COMPILER=$SDK/lib/llvm/bin/clang++
        #   -DCMAKE_PREFIX_PATH=$SDK;$SDK/lib/rocm_sysdeps;$SDK/lib/llvm
        #   -DCMAKE_HIP_FLAGS=--rocm-path=$SDK --rocm-device-lib-path=$SDK/lib/llvm/amdgcn/bitcode
        #
        # Внутри контейнера SDK смонтирован как /opt/Strata/rocm/install,
        # поэтому пути ниже — контейнерные.
        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -v "$STRATA_DIR:/opt/Strata:Z" \
          --entrypoint /bin/bash \
          "$IMAGE" \
          -c '
            set -e

            SDK=/opt/Strata/rocm/install

            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora.repo \
                        /etc/yum.repos.d/fedora-updates.repo \
                        /etc/yum.repos.d/fedora-updates-archive.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora/linux|g" "$repo"
            done
            for repo in /etc/yum.repos.d/fedora-cisco-openh264.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done
            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            echo "=== Устанавливаю cmake, ninja, gcc-c++, git ==="
            dnf5 install -y --setopt=install_weak_deps=False \
              cmake ninja-build gcc-c++ make git

            cd /opt/Strata

            echo "=== Конфигурирую CMake ==="
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

            echo "=== Собираю движок (может занять 25+ минут) ==="
            cmake --build build-halo --target strata -j "$(nproc)"
          '

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка завершена."
        echo "  Движок: $STRATA_DIR/build-halo/strata"
        echo "  Запуск: strata-start"
        echo "═══════════════════════════════════════════════════════════════"
      '';
    })

    # =====================================================================
    # Запуск сервисного контейнера с готовым движком.
    #
    # Модель указывается флагами `--model` и (опционально) `--speculative`
    # при первом запуске. Если модель уже лежит в ~/llm/strata/models/
    # и вы хотите использовать её по умолчанию — правьте переменную
    # MODEL_PATH ниже под свой файл.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-start";
      runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils pkgs.coreutils ];
      text = ''
        set -euo pipefail

        CONTAINER_NAME="strata-server"
        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        if [ ! -x "$STRATA_DIR/build-halo/strata" ]; then
          echo "Движок не собран. Сначала: strata-setup" >&2
          exit 1
        fi

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Создаю сервисный контейнер..."
          # Переменные ROCm-окружения передаются через -e.
          # LD_LIBRARY_PATH содержит:
          #   $SDK/lib                  — основные .so из ROCm
          #   $SDK/lib/rocm_sysdeps/lib — системные .so (zlib, elfutils)
          #   $SDK/lib/llvm/lib         — libLLVM/AMDGPU для clang
          # STRATA_HIPBLASLT_TUNING — таблица автотюнинга hipBLASLt
          # для gfx1151, лежит в самом репозитории Strata.
          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$STRATA_DIR:/opt/Strata:Z" \
            -e ROCM_PATH=/opt/Strata/rocm/install \
            -e HIP_PATH=/opt/Strata/rocm/install \
            -e LD_LIBRARY_PATH=/opt/Strata/rocm/install/lib:/opt/Strata/rocm/install/lib/rocm_sysdeps/lib:/opt/Strata/rocm/install/lib/llvm/lib \
            -e STRATA_HIPBLASLT_TUNING=/opt/Strata/${hipblasltTuning} \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c 'cd /opt/Strata && exec ./build-halo/strata serve --host 0.0.0.0 --port '"$PORT_CONTAINER"
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$STATUS" = "running" ]; then
          echo "Контейнер '$CONTAINER_NAME' уже запущен."
        else
          echo "Запускаю сервер (статус был: $STATUS)..."
          podman start "$CONTAINER_NAME"
        fi

        URL="http://localhost:$PORT_HOST"
        echo -n "Ожидание сервиса"
        for _ in {1..300}; do
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

    # === Остановка ===
    (pkgs.writeShellApplication {
      name = "strata-stop";
      runtimeInputs = [ pkgs.podman ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="strata-server"

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Сервисный контейнер не найден."
          exit 0
        fi

        STATUS=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        case "$STATUS" in
          running|paused|restarting)
            echo "Останавливаю..."
            podman stop -t 60 "$CONTAINER_NAME" 2>/dev/null || {
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

    # === Удаление ===
    (pkgs.writeShellApplication {
      name = "strata-remove";
      runtimeInputs = [ pkgs.podman pkgs.coreutils ];
      text = ''
        set -euo pipefail
        CONTAINER_NAME="strata-server"
        IMAGE="${image}"
        STRATA_DIR="${strataDir}"

        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

        if podman image exists "$IMAGE" 2>/dev/null; then
          read -r -p "Удалить образ '$IMAGE'? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            podman rmi "$IMAGE"
            echo "Образ удалён."
          else
            echo "Образ сохранён."
          fi
        fi

        if [ -d "$STRATA_DIR" ]; then
          SIZE=$(du -sh "$STRATA_DIR" 2>/dev/null | cut -f1 || echo "?")
          read -r -p "Удалить $STRATA_DIR ($SIZE — исходники + ROCm + модели)? [y/N] " answer
          if [[ "''${answer,,}" == "y" ]]; then
            rm -rf "$STRATA_DIR"
            echo "$STRATA_DIR удалён."
          else
            echo "$STRATA_DIR сохранён."
          fi
        fi
        echo "Готово."
      '';
    })

    # === Обновление (git pull + пересборка) ===
    # IMAGE здесь НЕ объявляется — переменная не используется в теле
    # (git pull и вызов strata-setup работают без неё). Раньше была
    # объявлена, но не использовалась — shellcheck ругался SC2034.
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        STRATA_DIR="${strataDir}"

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "Обновляю исходники (git pull)..."
        git -C "$STRATA_DIR" pull --ff-only

        echo
        echo "Пересборка движка (удаляю build-halo/)..."
        rm -rf "$STRATA_DIR/build-halo"

        echo
        echo "Запускаю strata-setup для пересборки (ROCm уже скачан)..."
        strata-setup
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    strata-setup = {
      name = "Strata Setup (first time)";
      exec = "strata-setup";
      icon = "system-software-install";
      terminal = true;
      categories = [ "Development" "Science" ];
    };
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
  };
}
