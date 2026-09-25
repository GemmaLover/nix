#!/usr/bin/env bash
# llm/unsloth/stop.sh
# Останавливает контейнер Unsloth. Данные в volume сохраняются.

set -euo pipefail

CONTAINER_NAME="unsloth"

if ! podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Контейнер '${CONTAINER_NAME}' не найден — нечего останавливать."
  exit 0
fi

if ! podman container running "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Контейнер уже остановлен."
  exit 0
fi

echo "Останавливаю контейнер..."
podman stop "${CONTAINER_NAME}"
echo "Готово."
