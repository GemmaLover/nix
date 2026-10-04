# Точка входа LLM-профиля.
#
# Активные модули:
#   ./dsh            — DeepSeek Harness (local: 7718, container: 7004)
#
# TODO: перенести остальные модули в подпапки:
#   ./unsloth/default.nix       — уже есть в llm/unsloth/
#   ./gufo/default.nix          — уже есть (сейчас deafult.nix, исправить)
#   ./cockpit/default.nix       — уже есть в llm/cockpit/
#   ./cockpit-toolboxes         — нет отдельной папки, файл в llm/deprecated/
#   ./system.nix                — системные настройки LLM
{ config, pkgs, ... }:

{
  imports = [
    ./dsh/default.nix
    ./unsloth/default.nix
    ./unsloth/commands.nix
    # остальные подключим позже
  ];
}
