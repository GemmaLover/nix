{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Gufo — движок инференса для AMD Strix Halo (gfx1151).
  #
  # Установка — через готовый Podman-образ, БЕЗ сборки:
  #   ghcr.io/gufo-org/toolboxes/gufo-runtime:latest
  #
  # Модель: Qwen3.8-Flash-Next UD-IQ4_XS (Unsloth Dynamic, 4-bit).
  # Разбита на 3 шарда (-00001/00002/00003-of-00003.gguf),
  # все должны лежать в одной папке. Gufo подтянет остальные
  # по имени первого файла.
  #
  # Пути на хосте:
  #   ~/llm/models/   — корень моделей, монтируется в /models (ro)
  #
  # Порт: 8640 (наружу и внутри — gufo serve --port 8640).
  # =====================================================================

  image = "ghcr.io/gufo-org/toolboxes/gufo-runtime:latest";

  # Порт на хосте и внутри контейнера. Оба 8640, чтобы не путаться:
  # `gufo serve --port 8640` и `-p 8640:8640`.
  portHost = 8640;
  portContainer = 8640;

  # Корень моделей. Монтируется как /models (ro).
  modelsDir = "${config.home.homeDirectory}/llm/models";

  # Путь к модели ВНУТРИ контейнера.
  # MAIN_MODEL идёт в `gufo serve --model ...`, gufo сам подтянет
  # -00002-of-00003 и -00003-of-00003 из той же папки.
  mainModel = "/models/unsloth-model/q3.8fn/ud_iq4_xs/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";

  # API-ключ (файл на хосте).
  apiKeyFile = "${config.home.homeDirectory}/.config/gufo/api-key";
in
{
  _module.args.gufoConfig = {
    inherit image portHost portContainer modelsDir mainModel apiKeyFile;
  };
}
