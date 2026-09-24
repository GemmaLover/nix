{ config, lib, pkgs, ... }:

{
  # === Скрипты ===
  # Управление подсветкой клавиатуры реализовано через systemd-сервисы
  # в devices/z13/home-services.nix. Здесь пока пусто.

  imports = [
    ./z13-uninstall.nix
  ];
}
