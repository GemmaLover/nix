{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Gufo — движок инференса для AMD Strix Halo (gfx1151).
  #
  # Структура:
  #   ~/llm/gufo/          — репозиторий (клонируется на хосте).
  #                          Монтируется в контейнер как /opt/gufo.
  #   ~/llm/models/gufo/   — .gguf-модели.
  #                          Монтируется в контейнер как /models (ro).
  #   ~/llm/gufo/.pip-cache/ — persistent pip-кэш (переживает обрывы).
  #
  # Образ-база: kyuz0/amd-strix-halo-toolboxes (ROCm 10.0, gfx1151) —
  # в нём уже есть ROCm runtime и все GPU-драйверы. Плюс инструменты
  # сборки ставятся через dnf5 внутри entrypoint.
  #
  # Двухэтапный workflow:
  #   1. gufo-setup  — интерактивная установка (сборка движка).
  #   2. gufo-start  — запуск сервера.
  #
  # Порт: 8087 (наружу) → 8087 (внутри).
  # =====================================================================

  image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20261010T195700";

  portHost = 8087;
  portContainer = 8087;

  # Репозиторий движка.
  gufoDir = "${config.home.homeDirectory}/llm/gufo";

  # Модели.
  modelsDir = "${config.home.homeDirectory}/llm/models/gufo";

  # Git-URL репозитория.
  repoUrl = "https://github.com/gufo-org/gufo.git";
in
{
  _module.args.gufoConfig = {
    inherit image portHost portContainer gufoDir modelsDir repoUrl;
  };
}
