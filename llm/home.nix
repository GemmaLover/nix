{ config, pkgs, ... }:

{
  # =====================================================================
  # LLM — агрегатор пользовательских модулей Home Manager.
  #
  # Каждый подмодуль отвечает за свой стек:
  #   - unsloth.nix            — Unsloth (ROCm-контейнер, веб-UI)
  #   - deepseek-harness.nix   — DeepSeek Harness (сборка из Git)
  #
  # Чтобы добавить новый LLM-стек (Ollama, vLLM, llama.cpp) —
  # создайте рядом файл и допишите его в imports.
  # =====================================================================

  imports = [
    ./unsloth.nix
    ./deepseek-harness.nix
  ];
}
