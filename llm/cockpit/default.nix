{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Cockpit AI Toolbox — TUI + два llama.cpp контейнера (ROCm, Vulkan).
  #
  # INI-режим:
  #   llama-server запускается с флагом --models-preset /models/models.ini.
  #   В models.ini описаны секции [*] (общие) и отдельные секции для
  #   каждой модели с её параметрами (ctx-size, temp, top-p, ...).
  #   Клиент выбирает модель по алиасу секции в API-запросе ("model": "...").
  #
  #   Шаблон models.ini создаётся автоматически при первом запуске
  #   (home.activation ниже). Существующий файл НЕ перезаписывается —
  #   это пользовательские данные, не декларативная конфигурация.
  #
  # Папка моделей: ~/llm/models/llama-cpp — общая для обоих контейнеров,
  # монтируется в /models. GGUF-файлы и models.ini лежат здесь.
  #
  # Порты:
  #   ROCm   — 8085 (наружу) → 8080 (внутри контейнера)
  #   Vulkan — 8086 (наружу) → 8080 (внутри контейнера)
  #   Оба можно запускать одновременно — порты не конфликтуют.
  # =====================================================================

  rocm = {
    containerName = "llama-rocm";
    image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20261005T170050";
    portHost = 8085;
    portContainer = 8080;
  };

  vulkan = {
    containerName = "llama-vulkan";
    image = "docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv_20261005T170128";
    portHost = 8086;
    portContainer = 8080;
  };

  modelsDir = "${config.home.homeDirectory}/llm/models/llama-cpp";

  # Шаблон models.ini. Записывается, если файл отсутствует.
  modelsIniTemplate = pkgs.writeText "llama-cpp-models.ini.template" ''
    version = 1

    [*]
    # Глобальные настройки для всех моделей.
    # Меняйте здесь параметры, общие для всех: port, ctx-size по умолчанию, flash-attn.
    host = 0.0.0.0
    port = 8080
    n-gpu-layers = 999
    flash-attn = on
    jinja = true
    mmap = off
    mlock = on
    ctx-size = 16384

    # ============================================================
    # Секции моделей. Имя секции = алиас модели в API ("model": "...").
    # model = /models/<filename>.gguf — путь ВНУТРИ контейнера,
    #                                    т.к. ~/llm/models/llama-cpp
    #                                    смонтирован в /models.
    #
    # Раскомментируйте и переименуйте секции под свои GGUF-файлы.
    # ============================================================

    # [Qwen-Coder-30B]
    # model = /models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
    # ctx-size = 32768
    # temp = 0.7
    # top-p = 0.95
    # top-k = 20
    # repeat-penalty = 1.05
    # load-on-startup = true

    # [Gemma-4-E4B]
    # model = /models/gemma-4-E4B-it-Q4_K_M.gguf
    # ctx-size = 16384
    # temp = 1.0
    # top-k = 64
    # load-on-startup = false
  '';

  ai-toolbox-cockpit = pkgs.callPackage ../../pkgs/ai-toolbox-cockpit { };
in
{
  _module.args.cockpitConfig = {
    inherit rocm vulkan modelsDir modelsIniTemplate ai-toolbox-cockpit;
  };
}
