{ config, lib, pkgs, ... }:

{
  # === LLM (Large Language Models) ===
  # Программы для работы с LLM запускаются в Podman-контейнерах.
  # Это позволяет изолировать зависимости и легко обновлять компоненты.

  # --- Пакеты, необходимые для работы с LLM ---
  environment.systemPackages = with pkgs; [
    # Инструменты для контейнеров
    podman-compose

    # Утилиты
    git
  ];

  # --- Пользовательские группы для LLM ---
  # Пользователь должен быть в группах kvm и libvirt для доступа к /dev/kvm
  # (уже добавлено в users.nix)

  # --- Скрипты для запуска LLM-контейнеров ---
  # Ярлыки и скрипты будут добавлены в base/system/scripts/

  # --- Unsloth ---
  # Контейнер для Unsloth: https://unsloth.ai/
  # Запуск: podman run --rm -it --gpus all -v ~/projects:/projects unsloth-container

  # --- DeepSeek Harness ---
  # Контейнер для DeepSeek Harness: https://github.com/deepseek-ai/deepseek-harness
  # Git-проект качается в ~/llm/dsharness
  # Запуск: podman run --rm -it -v ~/llm/dsharness:/app dsharness-container
}
