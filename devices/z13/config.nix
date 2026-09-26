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
    ../../base/tools/portmaster.nix

    # === Разделы ===
    ../../dev/dev.nix
    ../../llm/system.nix
    # ../../games/games.nix   # TODO: Добавить позже
  ];

  # =====================================================================
  # Обработка закрытия крышки через systemd-logind.
  #
  # KDE (PowerDevil) конфликтует с logind, из-за чего на AC закрытие
  # крышки игнорируется, а на Battery запускается гибернация без
  # блокировки экрана.
  #
  # Пользуемся встроенной логикой logind:
  #   HandleLidSwitch              — на батарее → hibernation
  #   HandleLidSwitchExternalPower — от сети → lock (блокировка через D-Bus)
  #   HandleLidSwitchDocked        — с док-станцией → ignore
  # =====================================================================
  services.logind.settings.Login = {
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
LidSwitchIgnoreInhibited = "no";
    # Задержка 5 секунд, чтобы KDE успел сохранить сессию
    # перед уходом в гибернацию (на случай, если у вас всё же
    # сработает гибернация через logind).
    HoldoffTimeoutSec = 5;
  };

  # Хостнейм для z13
  networking.hostName = "z13";

  # stateVersion — НЕ МЕНЯТЬ после установки
  system.stateVersion = "26.05";
}
