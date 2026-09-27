{ config, lib, pkgs, ... }:

{
  imports = [
    # === Специфичное для z13 ===
    ./hardware.nix                 # hardware-configuration.nix
    ./specific/kernel.nix          # Параметры ядра (amdgpu.gttsize, ttm.pages_limit)
    ./specific/asus-tools.nix      # asusctl, z13-tablet-kit, z13ctl-plus
    ./specific/z13-tools.nix
    ./specific/gpu-amd.nix
    ./specific/performance.nix
    ./specific/lid-daemon.nix

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

    ../../base/tools/signbox.nix
    ../../base/tools/n13rebuild.nix

    ../../base/tools/byedpi.nix
    ../../base/tools/zapret-tpws.nix

    # === UI ===
    ../../base/ui/kde.nix

    # === Программы ===
    ../../base/tools/base.nix
    ../../base/tools/flatpak.nix
#     ../../base/tools/portmaster.nix

    # === Разделы ===
    ../../dev/dev.nix
    ../../llm/system.nix
    # ../../games/games.nix   # TODO: Добавить позже
  ];
  # =====================================================================
  # Крышка теперь обрабатывается udev-правилом (см. specific/lid-handler.nix).
  # logind не должен вмешиваться, иначе будет двойное срабатывание.
  # =====================================================================
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;  # Автоматически включать адаптер при загрузке
};

  hardware.enableRedistributableFirmware = true;

  # Хостнейм для z13
  networking.hostName = "z13";

  # stateVersion — НЕ МЕНЯТЬ после установки
  system.stateVersion = "26.05";
}
