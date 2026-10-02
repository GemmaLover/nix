{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/hyprland/hyprland.nix — Wayland-композитор Hyprland (каркас).
  #
  # Создан при рефакторинге как точка входа миграции с KDE.
  # Здесь — минимальный системный слой; пользовательская настройка
  # (hyprland.conf, keybinds, бары) подключается через Home Manager
  # модулем programs.hyprland (см. devices/<n>/home-specific/).
  #
  # Чек-лист переноса функциональности из KDE:
  #   SDDM            -> greetd + tuigreet
  #   PowerDevil      -> power-profiles-daemon (уже есть) + hypridle
  #   kscreenlocker   -> hyprlock
  #   Plasma-виджет батареи для PPD -> waybar / ags
  #   bluedevil       -> bluez + networkmanager-applet или blueman
  #   plasma-manager  -> programs.hyprland в Home Manager
  # =====================================================================

  programs.hyprland = {
    enable = true;
    # EGL/XCB-обёртки: запуск X11-приложений и NVIDIA-совместимость.
    xwayland.enable = true;
  };

  # Менеджер входа: greetd вместо SDDM (SDDM тянет Qt/KDE-зависимости).
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --remember --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # Portal-бэкенд Hyprland (скриншоты, пикер файлов для Flatpak).
  # Основной gtk-портал подключён в ui/common/wayland.nix.
  environment.systemPackages = with pkgs; [
    xdg-desktop-portal-hyprland
  ];
}
