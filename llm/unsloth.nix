{ config, pkgs, ... }:

let
  # Общие переменные для всех скриптов.
  unslothVars = ''
    CONTAINER_NAME="unsloth"
    IMAGE="docker.io/unsloth/unsloth:latest"
    HOST_PROJECTS="''${HOME}/projects"
    DATA_VOLUME="unsloth-data"
  '';

  unslothInstall = pkgs.writeShellApplication {
    name = "unsloth-install";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      ${unslothVars}

      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "Контейнер уже существует. Запустите unsloth-remove."
        exit 1
      fi

      if ! podman image exists "$IMAGE" 2>/dev/null; then
        read -r -p "Скачать образ $IMAGE (~5–7 ГБ)? [y/N] " a
        [[ "''${a,,}" == "y" ]] || exit 1
        podman pull "$IMAGE"
      fi

      podman volume exists "$DATA_VOLUME" 2>/dev/null || podman volume create "$DATA_VOLUME"

      podman create \
        --name "$CONTAINER_NAME" \
        --device /dev/kfd --device /dev/dri \
        --group-add keep-groups \
        --security-opt label=disable \
        -p 8888:8888 -p 8000:8000 \
        -v "$HOST_PROJECTS:/workspace/host:Z" \
        -v "$DATA_VOLUME:/workspace/studio" \
        -e JUPYTER_PASSWORD=unsloth \
        "$IMAGE"

      echo "Готово. Запуск: unsloth-start"
    '';
  };

  unslothStart = pkgs.writeShellApplication {
    name = "unsloth-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      ${unslothVars}
      podman container running "$CONTAINER_NAME" 2>/dev/null || podman start "$CONTAINER_NAME"
      for _ in {1..60}; do
        curl -fsS -o /dev/null http://localhost:8000 2>/dev/null && break
        sleep 1
      done
      xdg-open http://localhost:8000 &
    '';
  };

  unslothStop = pkgs.writeShellApplication {
    name = "unsloth-stop";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      ${unslothVars}
      podman stop "$CONTAINER_NAME" 2>/dev/null || true
    '';
  };

  unslothRemove = pkgs.writeShellApplication {
    name = "unsloth-remove";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      ${unslothVars}
      podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
      read -r -p "Удалить volume $DATA_VOLUME? [y/N] " a
      [[ "''${a,,}" == "y" ]] && podman volume rm "$DATA_VOLUME" || true
      read -r -p "Удалить образ $IMAGE? [y/N] " a
      [[ "''${a,,}" == "y" ]] && podman rmi "$IMAGE" || true
    '';
  };
in
{
  home.packages = [
    unslothInstall
    unslothStart
    unslothStop
    unslothRemove
  ];
}
