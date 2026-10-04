{ config, pkgs, ... }:

let
  # Подключаем локальный пакет из pkgs/.
  # Путь ../pkgs/... потому что файл лежит в llm/, а pkgs/ — на уровень выше.
  ai-toolbox-cockpit = pkgs.callPackage ../pkgs/ai-toolbox-cockpit { };
in
{
  # Пользовательский пакет — в home.packages, а не в systemPackages.
  home.packages = [
    ai-toolbox-cockpit
  ];

  xdg.desktopEntries.ai-toolbox-cockpit = {
    name = "AI Toolbox Cockpit";
    genericName = "TUI for managing AI containers";
    exec = "ai-toolbox-cockpit";
    icon = "utilities-terminal";
    terminal = true;
    categories = [ "Development" "Science" ];
  };
}
