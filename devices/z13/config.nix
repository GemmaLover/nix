{ config, lib, pkgs, ... }:

{
  imports = [
    # === Специфичное для z13 ===
    ./hardware.nix                 # hardware-configuration.nix
    ./specific/kernel.nix          # Параметры ядра (amdgpu.gttsize, ttm.pages_limit)
    ./specific/asus-tools.nix      # asusctl, z13-tablet-kit, z13ctl-plus

    # === Базовые модули для всех устройств ===
    ../../base/system/boot.nix
    ../../base/system/network.nix
    ../../base/system/users.nix
    ../../base/system/keyboard.nix
    ../../base/system/luks.nix
    ../../base/system/apparmor.nix
    ../../base/system/audio.nix
    ../../base/system/dns.nix
    ../../base/system/scripts
    ../../base/system/touchpad.nix
    ../../base/system/time.nix

    # === UI ===
    ../../base/ui/kde.nix

    # === Программы ===
    ../../base/tools/base.nix
    ../../base/tools/flatpak.nix

    # === Разделы ===
    ../../dev/dev.nix
    ../../llm/llm.nix
    # ../../games/games.nix   # TODO: Добавить позже
  ];

  # Хостнейм для z13
  networking.hostName = "z13";

  # stateVersion — НЕ МЕНЯТЬ после установки
  system.stateVersion = "26.05";
}
