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

    # --- Зеркала Docker Hub ---
    # Docker Hub (docker.io) блокируется российскими провайдерами:
    # pull зависает на 0 B/s или идёт со скоростью 16 КБ/с.
    # Здесь перечислены зеркала, через которые Podman автоматически
    # проксирует запросы к docker.io.
    #
    # NixOS-модуль сам генерирует /etc/containers/registries.conf
    # из этих настроек (TOML-сериализация атрибутов). Прямая запись
    # через environment.etc не работает — конфликт с модулем.
    #
    # insecure = true: зеркала работают по HTTP без валидного
    # TLS-сертификата для docker.io. Это НЕ снижает безопасность:
    # Podman всё равно проверяет digest (SHA256) каждого слоя образа
    # после скачивания. insecure относится только к транспорту,
    # а не к целостности данных.
    #
    # Podman пробует зеркала в порядке перечисления. Если первое
    # возвращает 404 или таймаутит — переходит к следующему.
    containers.registries.settings = {
      registry = [
        {
          prefix = "docker.io";
          location = "docker.io";
          # Зеркала. Порядок: сначала самые быстрые/надёжные, потом резерв.
          mirror = [
            {
              # GitVerse — российское зеркало (СберТех), обычно самое быстрое из РФ.
              location = "dh-mirror.gitverse.ru";
              insecure = true;
            }
            {
              # Timeweb Cloud — российский хостинг, стабильное, но иногда медленнее GitVerse.
              location = "dockerhub.timeweb.cloud";
              insecure = true;
            }
            {
              # Beget — российский хостер, резервный вариант.
              location = "dockerhub1.beget.com";
              insecure = true;
            }
            {
              # Daocloud — китайское зеркало, часто работает быстро из РФ.
              location = "docker.m.daocloud.io";
              insecure = true;
            }
            {
              # Huecker.io — публичное зеркало без ограничений.
              location = "huecker.io";
              insecure = true;
            }
          ];
        }
      ];
    };
  };

  # --- Docker ---
  # Оставлен для случаев, когда Podman не подходит.
  # Для AI-инструментов используется Podman — он безопаснее (rootless).
  virtualisation.docker = {
    enable = true;
    # overlay2 — рекомендуемый драйвер.
    storageDriver = "overlay2";

    # Docker использует ту же конфигурацию зеркал, что и Podman
    # (общий файл /etc/containers/registries.conf, генерируется
    # из virtualisation.containers.registries.settings выше).
    # Отдельной настройки не требуется.
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
