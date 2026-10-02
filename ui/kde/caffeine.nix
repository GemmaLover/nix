{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/kde/caffeine.nix — caffeine-ng (ингибирование сна при видео).
  #
  # Перенесено из devices/z13/home-caffeine.nix: функционал не зависит
  # от железа z13 — это часть KDE-слоя. При миграции на Hyprland его
  # заменит systemd-inhibit / hypridle inhibit, файл переедет в ui/hyprland/.
  #
  # === Caffeine-ng ===
  # Автоматически блокирует засыпание и блокировку экрана,
  # когда приложение (Firefox, VLC и т.д.) запрашивает ингибирование.
  # Работает через D-Bus и MPRIS, поддерживает Wayland.
  #
  # ВАЖНО: caffeine-ng — это ТРЕЙ-приложение (user-сервис), а не
  # системный демон. В NixOS оно доступно как programs.caffeine-ng.enable
  # (Home Manager) — поэтому управление им лежит в home-слое устройства
  # (см. devices/<n>/home-specific/), а здесь подключается только
  # системная зависимость — сам пакет, чтобы он был в окружении.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    caffeine-ng
  ];

  # Трей-подобные сервисы Plasma (интеграция трея с caffeine) — на уровне
  # системы достаточно plasma6 (ui/kde/plasma.nix); сам запуск трей-аппа
  # выполняется Home Manager-модулем programs.caffeine-ng.
}
