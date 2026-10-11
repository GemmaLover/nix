{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Gufo — движок инференса для AMD Strix Halo (gfx1151).
  #
  # Установка — через готовый Podman-образ, БЕЗ git clone и сборки:
  #   ghcr.io/gufo-org/toolboxes/gufo-runtime:latest
  #
  # Модель: Qwen3.8-Flash-Next GSQ-RCO Q2_0 (ISTA-DASLab, 125B MoE).
  # Файлов два (-00001-of-00002 и -00002-of-00002), оба должны быть в
  # одной папке. Gufo сам подтянет второй по имени первого.
  #
  # API-ключ: Gufo требует ключ при запуске сервера. Ключ НЕ хранится
  # в Nix-конфиге. Лежит в файле:
  #   ~/.config/gufo/api-key
  # Создать один раз:
  #   mkdir -p ~/.config/gufo
  #   echo "ваш-ключ" > ~/.config/gufo/api-key
  #   chmod 600 ~/.config/gufo/api-key
  #
  # Пути на хосте:
  #   ~/llm/models/   — корень моделей, монтируется в /models (ro)
  #
  # Команды: gufo-start / gufo-stop / gufo-logs / gufo-models / gufo-remove.
  # =====================================================================

  image = "ghcr.io/gufo-org/toolboxes/gufo-runtime:latest";

  # Порт на хосте. Внутри контейнера всегда 8080.
  portHost = 8080;
  portContainer = 8080;

  # Корень моделей. Монтируется как /models (ro).
  modelsDir = "${config.home.homeDirectory}/llm/models";

  # Путь к модели ВНУТРИ контейнера.
  # Файл разбит на две части (-00001-of-00002 + -00002-of-00002),
  # обе должны лежать в одной папке.
  mainModel = "/models/ISTA-DASLab/q2_0/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf";

  # Путь к файлу с API-ключом на хосте.
  apiKeyFile = "${config.home.homeDirectory}/.config/gufo/api-key";
in
{
  _module.args.gufoConfig = {
    inherit image portHost portContainer modelsDir mainModel apiKeyFile;
  };
}
