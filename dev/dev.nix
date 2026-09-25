{ config, lib, pkgs, ... }:

{
  # === Разработка ===

  # --- Podman ---
  # Podman — rootless-альтернатива Docker
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      # Автоматически удалять неиспользуемые образы
      autoPrune.enable = true;
      # DNS для контейнеров
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # --- Docker ---
  # Docker с UI (для случаев, когда Podman не подходит)
  virtualisation.docker = {
    enable = true;
    # Использовать overlay2 — рекомендуемый драйвер
    storageDriver = "overlay2";
  };

  # --- Waydroid ---
  # Waydroid — запуск Android-приложений через LXC
  # Требует Wayland-сессию
  virtualisation.waydroid = {
    enable = true;
    # Использовать nftables (рекомендуется для NixOS)
    package = pkgs.waydroid-nftables;
  };

  # --- Пакеты для разработки ---
  environment.systemPackages = with pkgs; [
    # Python
    python3
    python3Packages.pip

    # Node.js для DeepSeek Harness
    nodejs_22
    pnpm

    # Утилиты
    wl-clipboard  # Буфер обмена для Wayland
  ];
}
