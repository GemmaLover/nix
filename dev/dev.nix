{ config, lib, pkgs, ... }:

{
  # === Контейнеризация ===

  # --- Podman ---
  # Rootless-альтернатива Docker. Используется для:
  #   - Unsloth (ROCm-контейнер)
  #   - DeepSeek Harness (не использует, но пусть будет)
  #   - llama.cpp toolboxes
  #   - AI Toolbox Cockpit (управление через Podman)
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      # Автоматически удалять неиспользуемые образы.
      autoPrune.enable = true;
      # DNS для контейнеров (нужен для podman-compose).
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # --- Docker ---
  # Оставлен для случаев, когда Podman не подходит.
  # Для AI-инструментов используется Podman — он безопаснее (rootless).
  virtualisation.docker = {
    enable = true;
    # overlay2 — рекомендуемый драйвер.
    storageDriver = "overlay2";
  };

  # --- Distrobox ---
  # Обёртка над Podman/Docker для создания контейнеров.
  # Нужна AI Toolbox Cockpit — он управляет контейнерами через Distrobox.
  # Устанавливается как системный пакет, потому что Cockpit ищет
  # команду `distrobox` в PATH.
  # (distrobox сам по себе — это скрипт, вызывающий podman/docker.)

  # --- Waydroid ---
  # Запуск Android-приложений через LXC.
  # Требует Wayland-сессию.
  virtualisation.waydroid = {
    enable = true;
    # nftables — рекомендуется для NixOS.
    package = pkgs.waydroid-nftables;
  };

  # === Пользовательские группы ===
  # Пользователь lexi должен быть в группе podman для rootless-режима.
  # Без этого podman не сможет создавать rootless-контейнеры.
  users.users.lexi.extraGroups = [ "podman" ];

  # === Пакеты для разработки и AI ===
  environment.systemPackages = with pkgs; [
    # Python
    python3
    python3Packages.pip

    # Node.js для DeepSeek Harness
    nodejs_22
    pnpm

    # Distrobox — управление контейнерами (нужен AI Toolbox Cockpit).
    distrobox

    # Утилиты
    wl-clipboard  # Буфер обмена для Wayland
  ];
}
