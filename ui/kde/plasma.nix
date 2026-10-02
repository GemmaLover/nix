{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/kde/plasma.nix — чистый KDE Plasma 6.
  #
  # Рефакторинг base/ui/kde.nix: из модуля удалено всё, что не является
  # Plasma-специфичным:
  #   * services.libinput (mkForce)      -> ui/common/input.nix
  #   * services.printing                -> ui/common/printing.nix
  #   * ASUS libinput quirks (0x0B05)    -> devices/z13/specific/asus-input.nix
  # =====================================================================

  # X11 включаем даже при Wayland-сессии: часть приложений требует XWayland.
  services.xserver.enable = true;

  # SDDM — логин-менеджер Plasma.
  # При миграции на Hyprland его можно отключить и заменить на greetd.
  services.displayManager.sddm.enable = true;

  # Собственно Plasma 6.
  services.desktopManager.plasma6.enable = true;

  # Qt-компоненты, нужные именно Plasma (не тянутся автоматически).
  environment.systemPackages = with pkgs; [
    kdePackages.bluedevil   # Bluetooth-трей/диалоги для Plasma
  ];
}
