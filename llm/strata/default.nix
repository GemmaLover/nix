{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Strata — движок для Qwen3.8-Flash-Next (125B MoE).
  #
  # Работает на AMD Strix Halo (gfx1151) через HIP/ROCm.
  # Готового Docker-образа для AMD нет — setup.sh сам компилирует
  # движок и ИНТЕРАКТИВНО спрашивает модель, контекст, vision.
  #
  # ВАЖНО — где живут данные:
  #   ~/llm/strata/          ← ВСЁ на хосте (исходники, движок, модели)
  #   монтируется в /opt/Strata внутри контейнера.
  #
  #   То есть когда setup.sh внутри контейнера делает git clone и
  #   скачивает модель — файлы реально появляются в ~/llm/strata
  #   на хосте. Они переживают удаление контейнера.
  #
  # Модели: ~/llm/strata/models/ (setup.sh спросит путь — укажи его).
  #
  # Двухэтапный workflow:
  #   1. strata-setup  — интерактивная установка (podman run --rm -it).
  #   2. strata-start  — сервисный контейнер с уже собранным движком.
  #
  # Образ-база: kyuz0/amd-strix-halo-toolboxes (ROCm 10.0, gfx1151).
  # Порт: 5747.
  # =====================================================================

    image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20261010T195700";

  portHost = 5747;
  portContainer = 5747;

  # Всё в одну папку: ~/llm/strata.
  # Структура после setup:
  #   ~/llm/strata/.git/        — исходники Strata (git clone)
  #   ~/llm/strata/build/       — скомпилированный движок
  #   ~/llm/strata/models/      — GGUF-модели
  strataDir = "${config.home.homeDirectory}/llm/strata";
in
{
  _module.args.strataConfig = {
    inherit image portHost portContainer strataDir;
  };
}
