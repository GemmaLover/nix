{ config, lib, pkgs, ... }:

{
  imports = [
    # === Оси конфигурации (см. lib/options.nix) ===
    # Оболочка и профили подключаются диспетчерами (ui/default.nix,
    # profiles/default.nix), которые подставляет lib/mkSystem.nix.
    # Устройство лишь объявляет, ЧТО из осей ему нужно:
    #   ui       — kde | hyprland | none
    #   profiles — dev | llm | games (отличия машин только в llm/games)
    kda.opts = {
      ui = "kde";                     # TODO(миграция): "hyprland"
      profiles = [ "dev" "llm" ];     # games — позже
    };

    # === Специфичное для z13 (железо, ядро, vendor-утилиты) ===
    ./hardware.nix                 # hardware-configuration.nix
    ./specific/kernel.nix          # Параметры ядра (amdgpu.gttsize, ttm.pages_limit)
    ./specific/asus-tools.nix      # asusctl, z13-tablet-kit, z13ctl-plus
    ./specific/asus-input.nix      # libinput-квирк ASUS (перенесён из base/ui/kde.nix)
    ./specific/z13-tools.nix
    ./specific/gpu-amd.nix
    ./specific/performance.nix
    ./specific/lid-daemon.nix
    ./specific/touchpad.nix        # перенесён из base/system/touchpad.nix
    ./specific/uninstall-helper.nix # перенесён из base/system/scripts/

    # === Базовые модули для всех устройств (DE- и железо-независимые) ===
    ../../base/system/boot.nix
    ../../base/system/network.nix
    ../../base/system/users.nix
    ../../base/system/keyboard.nix
    ../../base/system/luks.nix
    ../../base/system/apparmor.nix
    ../../base/system/audio.nix
    ../../base/system/dns.nix      # sing-box DNS + zapret — база для всех
    ../../base/system/time.nix
    ../../base/system/nix-settings.nix  # nix-command/flakes на уровне системы (без --extra-experimental-features)

    ../../base/tools/signbox.nix
    ../../base/tools/n13rebuild.nix
    ../../base/tools/nfqws2.nix
    ../../base/tools/blockcheckw.nix

    # === Базовое ПО для всех ===
    ../../base/tools/base.nix
    ../../base/tools/flatpak.nix
#     ../../base/tools/portmaster.nix

    # Сюда НЕ переносим:
    #   ../../base/ui/kde.nix        -> ось ui (kda.opts.ui = "kde")
    #   ../../base/system/scripts    -> z13-скрипт лежит в ./specific/
    #   ../../dev/dev.nix            -> ось profiles ("dev")
    #   ../../llm/system.nix         -> ось profiles ("llm")
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
