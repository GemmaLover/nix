{ config, pkgs, ... }:

let
  # Общие переменные для всех скриптов Unsloth.
  unslothVars = ''
    CONTAINER_NAME="unsloth"
    IMAGE="docker.io/unsloth/unsloth:latest"
    HOST_PROJECTS="''${HOME}/projects"
    DATA_VOLUME="unsloth-data"
  '';

  unslothInstall = pkgs.writeShellApplication {
    name = "unsloth-install";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -euo pipefail
      ${unslothVars}
      # ... содержимое ...
    '';
  };

  unslothStart = pkgs.writeShellApplication {
    name = "unsloth-start";
    runtimeInputs = [ pkgs.podman pkgs.curl pkgs.xdg-utils ];
    text = ''
      set -euo pipefail
      ${unslothVars}
      # ... содержимое ...
    '';
  };

  # ... unsloth-stop, unsloth-remove ...

in
{
  home.packages = [
    unslothInstall
    unslothStart
    unslothStop
    unslothRemove
  ];

  # .desktop-ярлыки для запуска/остановки из меню приложений.
  xdg.desktopEntries = {
    unsloth-start = {
      name = "Unsloth Start";
      exec = "unsloth-start";
      icon = "utilities-terminal";
      categories = [ "Development" ];
    };
    unsloth-stop = {
      name = "Unsloth Stop";
      exec = "unsloth-stop";
      icon = "process-stop";
      categories = [ "Development" ];
    };
  };
}
