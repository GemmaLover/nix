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

  # --- Docker Hub зеркала ---
  # Docker Hub (docker.io) блокируется российскими провайдерами:
  # pull зависает на 0 B/s или идёт со скоростью 16 КБ/с.
  # Здесь перечислены зеркала, через которые Podman автоматически
  # проксирует запросы к docker.io.
  #
  # Используется прямой /etc/containers/registries.conf — это
  # официальный и стабильный способ, не зависящий от версии NixOS.
  # Опция virtualisation.containers.registries.registry удалена,
  # а virtualisation.containers.registries.settings имеет неочевидный
  # синтаксис и может измениться.
  #
  # insecure = true: зеркала работают по HTTP без валидного TLS-сертификата
  # для docker.io. Это НЕ снижает безопасность: Podman всё равно проверяет
  # digest (SHA256) каждого слоя образа после скачивания.
  #
  # Podman пробует зеркала в порядке перечисления. Если первое
  # возвращает 404 или таймаутит — переходит к следующему.
  environment.etc."containers/registries.conf".text = ''
    # Зеркала Docker Hub для обхода блокировки в РФ.
    # Порядок: сначала самые быстрые/надёжные, потом резервные.
    [[registry]]
    prefix = "docker.io"
    location = "docker.io"
    [[registry.mirror]]
    location = "dh-mirror.gitverse.ru"
    insecure = true
    [[registry.mirror]]
    location = "dockerhub.timeweb.cloud"
    insecure = true
    [[registry.mirror]]
    location = "dockerhub1.beget.com"
    insecure = true
    [[registry.mirror]]
    location = "docker.m.daocloud.io"
    insecure = true
    [[registry.mirror]]
    location = "huecker.io"
    insecure = true
  '';

  # --- Docker ---
  # Оставлен для случаев, когда Podman не подходит.
  # Для AI-инструментов используется Podman — он безопаснее (rootless).
  virtualisation.docker = {
    enable = true;
    # overlay2 — рекомендуемый драйвер.
    storageDriver = "overlay2";

    # Docker использует ту же конфигурацию зеркал, что и Podman
    # (общий файл /etc/containers/registries.conf). Отдельной
    # настройки не требуется.
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
