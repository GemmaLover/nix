{ config, pkgs, ... }:

let
  # =====================================================================
  # Управление Podman-контейнерами для AI Toolbox Cockpit.
  #
  # Скрипты аналогичны Unsloth: install / start / stop / remove.
  # Имена контейнеров: <тип>-<номер>-<дата>-<версия>
  #
  # Требования:
  #   - Пользователь в группах video и render
  #   - Параметры ядра: amd_iommu=off, amdgpu.gttsize=126976,
  #     ttm.pages_limit=32505856
  # =====================================================================

  # --- ROCm контейнер (llama.cpp) ---
  rocmInstall = pkgs.writeShellApplication {
    name = "llama-rocm-install";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-rocm-1-26092026-rocm-10.0_20260910T124956"
      IMAGE="docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20260910T124956"
      MODELS_DIR="$HOME/models"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже существует. Для пересоздания: llama-rocm-remove"
        exit 1
      fi

      if ! podman image exists "$IMAGE" 2>/dev/null; then
        read -r -p "Скачать образ (~1.3 ГБ)? [y/N] " answer
        [[ "''${answer,,}" == "y" ]] || exit 1
        podman pull "$IMAGE"
      fi

      mkdir -p "$MODELS_DIR"
      podman create \
        --name "$CONTAINER_NAME" \
        --device /dev/kfd --device /dev/dri \
        --group-add keep-groups \
        --security-opt label=disable \
        --shm-size=8g \
        -p 8085:8080 \
        -v "$MODELS_DIR:/models:Z" \
        "$IMAGE"

      echo "Контейнер создан. Запуск: llama-rocm-start"
    '';
  };

  # --- Vulkan контейнер (llama.cpp) ---
  vulkanInstall = pkgs.writeShellApplication {
    name = "llama-vulkan-install";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-vulkan-1-26092026-vulkan-radv_20260917T042352"
      IMAGE="docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv_20260917T042352"
      MODELS_DIR="$HOME/models"

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже существует. Для пересоздания: llama-vulkan-remove"
        exit 1
      fi

      if ! podman image exists "$IMAGE" 2>/dev/null; then
        read -r -p "Скачать образ (~573 МБ)? [y/N] " answer
        [[ "''${answer,,}" == "y" ]] || exit 1
        podman pull "$IMAGE"
      fi

      mkdir -p "$MODELS_DIR"
      podman create \
        --name "$CONTAINER_NAME" \
        --device /dev/dri \
        --group-add video \
        --security-opt label=disable \
        --shm-size=8g \
        -p 8085:8080 \
        -v "$MODELS_DIR:/models:Z" \
        "$IMAGE"

      echo "Контейнер создан. Запуск: llama-vulkan-start"
    '';
  };

  # --- Запуск ---
  rocmStart = pkgs.writeShellApplication {
    name = "llama-rocm-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-rocm-1-26092026-rocm-10.0_20260910T124956"
      URL="http://localhost:8085"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер не найден. Сначала: llama-rocm-install" >&2
        exit 1
      fi

      podman start "$CONTAINER_NAME" 2>/dev/null || true

      echo -n "Ожидание сервиса"
      for _ in {1..90}; do
        if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
          echo " — готов."
          break
        fi
        echo -n "."
        sleep 1
      done
      xdg-open "$URL" &
    '';
  };

  vulkanStart = pkgs.writeShellApplication {
    name = "llama-vulkan-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-vulkan-1-26092026-vulkan-radv_20260917T042352"
      URL="http://localhost:8085"

      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер не найден. Сначала: llama-vulkan-install" >&2
        exit 1
      fi

      podman start "$CONTAINER_NAME" 2>/dev/null || true

      echo -n "Ожидание сервиса"
      for _ in {1..90}; do
        if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
          echo " — готов."
          break
        fi
        echo -n "."
        sleep 1
      done
      xdg-open "$URL" &
    '';
  };

  # --- Остановка ---
  rocmStop = pkgs.writeShellApplication {
    name = "llama-rocm-stop";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-rocm-1-26092026-rocm-10.0_20260910T124956"
      podman stop "$CONTAINER_NAME" 2>/dev/null || true
    '';
  };

  vulkanStop = pkgs.writeShellApplication {
    name = "llama-vulkan-stop";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-vulkan-1-26092026-vulkan-radv_20260917T042352"
      podman stop "$CONTAINER_NAME" 2>/dev/null || true
    '';
  };

  # --- Удаление ---
  rocmRemove = pkgs.writeShellApplication {
    name = "llama-rocm-remove";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-rocm-1-26092026-rocm-10.0_20260910T124956"
      IMAGE="docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20260910T124956"

      podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

      read -r -p "Удалить образ? [y/N] " answer
      [[ "''${answer,,}" == "y" ]] && podman rmi "$IMAGE" || true
      echo "Готово."
    '';
  };

  vulkanRemove = pkgs.writeShellApplication {
    name = "llama-vulkan-remove";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      CONTAINER_NAME="llama-vulkan-1-26092026-vulkan-radv_20260917T042352"
      IMAGE="docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv_20260917T042352"

      podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

      read -r -p "Удалить образ? [y/N] " answer
      [[ "''${answer,,}" == "y" ]] && podman rmi "$IMAGE" || true
      echo "Готово."
    '';
  };

in
{
  home.packages = [
    rocmInstall vulkanInstall
    rocmStart vulkanStart
    rocmStop vulkanStop
    rocmRemove vulkanRemove
  ];

  xdg.desktopEntries = {
    llama-rocm-start = {
      name = "llama.cpp ROCm Start";
      exec = "llama-rocm-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
    llama-vulkan-start = {
      name = "llama.cpp Vulkan Start";
      exec = "llama-vulkan-start";
      icon = "utilities-terminal";
      terminal = false;
      categories = [ "Development" "Science" ];
    };
  };
}
