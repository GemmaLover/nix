{ config, pkgs, lib, strataConfig, ... }:

let
  inherit (strataConfig) image portHost portContainer strataDir;
in
{
  home.packages = [
    # =====================================================================
    # Одноразовая установка Strata. ИНТЕРАКТИВНАЯ.
    #
    # ПОДВОДНЫЕ КАМНИ ОБРАЗА kyuz0/amd-strix-halo-toolboxes:
    #   1. В образе НЕТ git — репозиторий клонируется НА ХОСТЕ,
    #      а внутрь контейнера монтируется готовое дерево.
    #   2. В образе НЕТ инструментов сборки (gcc-c++, make) — они
    #      ставятся через dnf5 внутри контейнера перед setup.sh.
    #      Образ — Fedora 44 Container Image с dnf5 (новое поколение).
    #   3. Fedora-репозитории и AMD ROCm-репозиторий недоступны из РФ:
    #      fedora.ip-connect.info и stable.repo.amd.com дают timeout.
    #      Поэтому ПЕРЕД установкой переключаем зеркала Fedora на
    #      доступные (ftp.fau.de + mirror.yandex.ru как резерв),
    #      а ROCm-репозиторий отключаем (ROCm уже в образе).
    #
    # Порядок:
    #   1. git clone на хосте → ~/llm/strata
    #   2. podman run --rm -it с монтированием ~/llm/strata → /opt/Strata
    #   3. Внутри контейнера: смена зеркал → dnf5 install → ./setup.sh
    #
    # setup.sh спросит модель, размер, контекст, KV cache, vision.
    # Когда спросит путь для моделей — указывать /opt/Strata/models
    # (это = ~/llm/strata/models на хосте).
    #
    # После выхода контейнер удаляется (--rm), но ВСЁ остаётся в
    # ~/llm/strata: исходники, скомпилированный движок, модели.
    # =====================================================================
    (pkgs.writeShellApplication {
      name = "strata-setup";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"
        PORT_HOST=${toString portHost}
        PORT_CONTAINER=${toString portContainer}

        mkdir -p "$STRATA_DIR"

        # === Шаг 1: клонируем/обновляем Strata НА ХОСТЕ ===
        # В образе kyuz0 нет git — поэтому клонируем здесь, где git есть.
        # Дальше монтируем готовое дерево в контейнер.
        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Клонирую Strata в $STRATA_DIR..."
          git clone https://github.com/Niko1221/Strata.git "$STRATA_DIR"
        else
          echo "Обновляю Strata (git pull)..."
          git -C "$STRATA_DIR" pull --ff-only || echo "  (git pull пропущен)"
        fi

        if [ ! -x "$STRATA_DIR/setup.sh" ]; then
          echo "ОШИБКА: в $STRATA_DIR нет setup.sh" >&2
          echo "Проверьте содержимое: ls $STRATA_DIR" >&2
          exit 1
        fi

        if ! podman image exists "$IMAGE" 2>/dev/null; then
          echo "Образ '$IMAGE' отсутствует. Скачиваю..."
          podman pull "$IMAGE"
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Установка Strata (интерактивная)."
        echo
        echo "  Исходники, движок и модели будут в: $STRATA_DIR"
        echo "  Когда setup.sh спросит путь для моделей — укажи:"
        echo "    /opt/Strata/models"
        echo "  (это то же самое, что $STRATA_DIR/models на хосте)"
        echo "═══════════════════════════════════════════════════════════════"
        echo

        # === Шаг 2: запускаем setup.sh ВНУТРИ контейнера ===
        # Репозиторий уже на месте (через bind mount).
        # Перед setup.sh:
        #   a) переключаем Fedora-зеркала на доступные из РФ,
        #   b) отключаем AMD ROCm-репозиторий (недоступен + ROCm уже в образе),
        #   c) ставим gcc-c++, make, git через dnf5,
        #   d) запускаем setup.sh.
        #
        # -it для интерактивного setup.sh (спрашивает модель и параметры).
        # --rm: контейнер удаляется после setup, всё ценное в $STRATA_DIR.
        podman run --rm -it \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt label=disable \
          --shm-size=8g \
          -p "$PORT_HOST:$PORT_CONTAINER" \
          -v "$STRATA_DIR:/opt/Strata:Z" \
          --entrypoint /bin/bash \
          "$IMAGE" \
          -c '
            set -e

            # === Шаг A: смена зеркал Fedora ===
            # По умолчанию в /etc/yum.repos.d/fedora*.repo стоит metalink=,
            # который сам выбирает зеркало и часто выбирает недоступное
            # из РФ (fedora.ip-connect.info — timeout).
            # Отключаем metalink, включаем baseurl с зеркалом, которое
            # проверено как доступное (см. результаты теста скорости).
            #
            # Выбор зеркала:
            #   ftp.fau.de       — 0.49s (самое быстрое из проверенных)
            #   mirror.yandex.ru — 2.07s (надёжный резерв, если FAU упадёт)
            #
            # Заменяем $releasever на 44 — в образе Fedora 44, а переменная
            # в некоторых зеркалах может не подставляться.
            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora*.repo; do
              [ -f "$repo" ] || continue
              # Отключаем metalink
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              # Заменяем placeholder-baseurl на реальный URL зеркала.
              # Формат по умолчанию: baseurl=http://download.example/pub/fedora/linux/...
              # Меняем только те baseurl, что начинаются с download.example,
              # и только если они раскомментированы.
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora|g" "$repo"
            done

            # === Шаг B: отключение AMD ROCm-репозитория ===
            # stable.repo.amd.com недоступен из РФ (timeout >30s).
            # ROCm уже вшит в образ, дополнительно тянуть не нужно.
            # Отключаем, чтобы dnf не висел на нём.
            echo "=== Отключаю AMD ROCm-репозиторий (недоступен из РФ) ==="
            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            # === Шаг C: установка инструментов сборки ===
            # dnf5 — новый менеджер Fedora 44+. Пробуем по убыванию:
            # dnf5 → microdnf → dnf (на случай другого образа).
            # install_weak_deps=False экономит ~200 МБ.
            if command -v dnf5 >/dev/null 2>&1; then
              echo "=== Установка gcc-c++, make, git через dnf5 ==="
              dnf5 install -y --setopt=install_weak_deps=False \
                gcc-c++ make git
            elif command -v microdnf >/dev/null 2>&1; then
              echo "=== Установка gcc-c++, make, git через microdnf ==="
              microdnf install -y --setopt=install_weak_deps=0 \
                gcc-c++ make git
            elif command -v dnf >/dev/null 2>&1; then
              echo "=== Установка gcc-c++, make, git через dnf ==="
              dnf install -y --setopt=install_weak_deps=False \
                gcc-c++ make git
            else
              echo "Неизвестный пакетный менеджер." >&2
              exit 1
            fi

            # === Шаг D: setup.sh ===
            cd /opt/Strata && ./setup.sh
          '

        echo
        echo "Установка завершена."
        echo "Всё лежит в: $STRATA_DIR"
        echo "Запуск сервера: strata-start"
      '';
    })

    # =====================================================================
    # Сервисный контейнер. Использует уже собранный движок из ~/llm/strata.
    #
    # Создаётся один раз (при первом вызове), потом только start/stop.
    # Entrypoint НЕ запускает setup.sh — только сервер.
    #
    # ВАЖНО: команда запуска сервера (`./start.sh --host ... --port ...`)
    # взята из общего описания. Если в репозитории Strata нет start.sh —
    # замените на ту, что описана в README. Проверить после setup:
    #   ls ~/llm/strata/*.sh
    #   cat ~/llm/strata/README.md | grep -i 'run\|start\|serve'
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

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена в $STRATA_DIR" >&2
          echo "Сначала выполните: strata-setup" >&2
          exit 1
        fi

        if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
          echo "Создаю сервисный контейнер..."
          podman create \
            --name "$CONTAINER_NAME" \
            --device /dev/kfd \
            --device /dev/dri \
            --group-add keep-groups \
            --security-opt label=disable \
            --shm-size=8g \
            -p "$PORT_HOST:$PORT_CONTAINER" \
            -v "$STRATA_DIR:/opt/Strata:Z" \
            --entrypoint /bin/bash \
            "$IMAGE" \
            -c "cd /opt/Strata && exec ./start.sh --host 0.0.0.0 --port ${toString portContainer}"
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
    # Плавно шлёт SIGTERM, ждёт до 60 секунд. Если не сработало — SIGKILL.
    # Файлы в ~/llm/strata не затрагиваются.
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
    # Удаляет контейнер, опционально образ, опционально ~/llm/strata
    # (исходники + модели). Спрашивает подтверждение на каждый шаг.
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
          read -r -p "Удалить $STRATA_DIR ($SIZE — исходники + модели)? [y/N] " answer
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
    # Клонирование и pull делает ХОСТ (где есть git), в контейнере
    # запускается только setup.sh — та же схема, что в strata-setup.
    # Зеркала Fedora переключаются заново (контейнер --rm, состояние
    # не сохраняется между запусками).
    (pkgs.writeShellApplication {
      name = "strata-update";
      runtimeInputs = [ pkgs.podman pkgs.git pkgs.coreutils ];
      text = ''
        set -euo pipefail

        IMAGE="${image}"
        STRATA_DIR="${strataDir}"

        if [ ! -d "$STRATA_DIR/.git" ]; then
          echo "Strata не установлена. Сначала: strata-setup" >&2
          exit 1
        fi

        echo "Обновляю исходники (git pull на хосте)..."
        git -C "$STRATA_DIR" pull --ff-only

        echo
        echo "Пересборка (setup.sh в контейнере)..."
        echo "setup.sh снова спросит модель — можно оставить ту же."
        echo

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

            # Та же смена зеркал, что в strata-setup.
            echo "=== Переключаю Fedora на зеркало ftp.fau.de ==="
            for repo in /etc/yum.repos.d/fedora*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^metalink=|#metalink=|g" "$repo"
              sed -i "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora|g" "$repo"
              sed -i "s|^baseurl=http://download.example/pub/fedora/linux|baseurl=https://ftp.fau.de/fedora|g" "$repo"
            done

            echo "=== Отключаю AMD ROCm-репозиторий ==="
            for repo in /etc/yum.repos.d/rocm*.repo; do
              [ -f "$repo" ] || continue
              sed -i "s|^enabled=1|enabled=0|g" "$repo"
            done

            if command -v dnf5 >/dev/null 2>&1; then
              dnf5 install -y --setopt=install_weak_deps=False gcc-c++ make git
            elif command -v microdnf >/dev/null 2>&1; then
              microdnf install -y --setopt=install_weak_deps=0 gcc-c++ make git
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y --setopt=install_weak_deps=False gcc-c++ make git
            fi

            cd /opt/Strata && ./setup.sh
          '

        echo
        echo "Обновление завершено. Перезапустите сервер:"
        echo "  strata-stop && strata-start"
      '';
    })
  ];

  # === Ярлыки в меню приложений ===
  xdg.desktopEntries = {
    strata-setup = {
      name = "Strata Setup (first time)";
      exec = "strata-setup";
      icon = "system-software-install";
      terminal = true;   # setup интерактивный, нужен терминал
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
