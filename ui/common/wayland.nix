{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/common/wayland.nix — Wayland-слой, общий для KDE и Hyprland.
  #
  # Сюда вынесено всё, что не зависит от конкретной оболочки:
  #   * сам Wayland (xdg-desktop-portal выбирается по DE автоматически);
  #   * wl-clipboard — доступ к буферу обмена из скриптов;
  #   * portal-зависимости (xdg-desktop-portal-gtk как fallback).
  #
  # При переходе на Hyprland этот файл НЕ меняется — меняются только
  # модули в ui/kde/ -> ui/hyprland/.
  # =====================================================================

  # Включаем поддержку Wayland-сессий на системном уровне.
  # programs.wayland.enable не существует в nixpkgs — Wayland включается
  # самими DE (plasma6/hyprland); пакетный слой ниже это portals + wl-clipboard.

  environment.systemPackages = with pkgs; [
    # Буфер обмена Wayland (используется скриптами и LLM-обёртками).
    wl-clipboard

    # Fallback-портал: обязателен для GTK/Electron/Flatpak-приложений,
    # когда основной backend (kde/hyprland portal) не покрывает запрос.
    xdg-desktop-portal-gtk
  ];
}
