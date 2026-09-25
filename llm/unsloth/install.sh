#!/usr/bin/env bash
# llm/unsloth/install.sh
# Одноразовая установка контейнера Unsloth.
# Запускать вручную. Ничего не скачивает без подтверждения.

set -euo pipefail

CONTAINER_NAME="unsloth"
IMAGE="docker.io/unsloth/unsloth:latest"    # ← проверьте имя после шага 2
HOST_PROJECTS="${HOME}/projects"
DATA_VOLUME="unsloth-data"

# --- Проверки ---
if ! command -v podman >/dev/null 2>&1; then
  echo "Ошибка: podman не найден в PATH." >&2
  exit 1
fi

if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Контейнер '${CONTAINER_NAME}' уже существует."
  echo "Чтобы пересоздать: сначала запустите remove.sh"
  exit 1
fi

# --- Образ ---
if podman image exists "${IMAGE}" 2>/dev/null; then
  echo "Образ '${IMAGE}' уже есть локально."
else
  echo "Образ '${IMAGE}' не найден локально."
  read -r -p "Скачать его сейчас (~5–7 ГБ)? [y/N] " answer
  if [[ "${answer,,}" != "y" ]]; then
    echo "Отменено."
    exit 1
  fi
  podman pull "${IMAGE}"
fi

# --- Persistent volume для моделей и настроек ---
if ! podman volume exists "${DATA_VOLUME}" 2>/dev/null; then
  podman volume create "${DATA_VOLUME}"
  echo "Создан volume '${DATA_VOLUME}' для persistent-данных."
fi

# --- Создание контейнера (без запуска) ---
# --device /dev/kfd --device /dev/dri — проброс AMD GPU
# --group-add keep-groups — сохраняет supplementary-группы пользователя
# --security-opt label=disable — снимает SELinux-метки (безвредно в NixOS)
podman create \
  --name "${CONTAINER_NAME}" \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add keep-groups \
  --security-opt label=disable \
  -p 8888:8888 \
  -p 8000:8000 \
  -v "${HOST_PROJECTS}:/workspace/host:Z" \
  -v "${DATA_VOLUME}:/workspace/studio" \
  -e JUPYTER_PASSWORD="unsloth" \
  "${IMAGE}"

echo
echo "Контейнер '${CONTAINER_NAME}' создан."
echo "Запуск:   llm/unsloth/start.sh"
echo "Остановка: llm/unsloth/stop.sh"
echo "Удаление: llm/unsloth/remove.sh"
