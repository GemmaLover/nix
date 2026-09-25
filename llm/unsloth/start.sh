#!/usr/bin/env bash
# llm/unsloth/start.sh
# Запуск уже созданного контейнера Unsloth.
# Ничего не скачивает и не обновляет.

set -euo pipefail

CONTAINER_NAME="unsloth"
URL_STUDIO="http://localhost:8000"
URL_JUPYTER="http://localhost:8888"

if ! podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Контейнер '${CONTAINER_NAME}' не найден." >&2
  echo "Сначала запустите: llm/unsloth/install.sh" >&2
  exit 1
fi

if podman container running "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Контейнер уже запущен."
else
  echo "Запускаю контейнер..."
  podman start "${CONTAINER_NAME}"
fi

# Ждём, пока сервис внутри поднимется (макс. 60 секунд).
echo -n "Ожидание сервиса"
for _ in {1..60}; do
  if curl -fsS -o /dev/null "${URL_STUDIO}" 2>/dev/null; then
    echo " — готов."
    break
  fi
  echo -n "."
  sleep 1
done

echo "Открываю ${URL_STUDIO}"
xdg-open "${URL_STUDIO}" &
