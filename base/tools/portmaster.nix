{ config, lib, pkgs, ... }:

{
  # Официальный модуль Portmaster из nixpkgs-unstable.
  # Включает ядро, GUI и системные сервисы.
  services.portmaster = {
    enable = true;
    settings = {
      "core/log/level" = "warning";
    };
  };
}
