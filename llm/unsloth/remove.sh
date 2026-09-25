#!/usr/bin/env bash
# llm/unsloth/remove.sh
# Полное удаление контейнера Unsloth.
# Образ и volume удаляются только с подтверждения.

set -euo pipefail

CONTAINER_NAME="unsloth"
DATA_VOLUME="unsloth-data"
IMAGE="docker.io/unsloth/unsloth:latest"

if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Удаляю контейнер '${CONTAINER_NAME}'..."
  podman rm -f "${CONTAINER_NAME}"
else
  echo "Контейнер '${CONTAINER_NAME}' уже отсутствует."
fi

if podman volume exists "${DATA_VOLUME}" 2>/dev/null; then
  read -r -p "Удалить volume '${DATA_VOLUME}' (модели и настройки Unsloth)? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    podman volume rm "${DATA_VOLUME}"
    echo "Volume удалён."
  else
    echo "Volume сохранён."
  fi
fi

if podman image exists "${IMAGE}" 2>/dev/null; then
  read -r -p "Удалить образ '${IMAGE}' (~5–7 ГБ)? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    podman rmi "${IMAGE}"
    echo "Образ удалён."
  else
    echo "Образ сохранён."
  fi
fi

echo "Готово."
