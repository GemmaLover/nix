{ config, lib, pkgs, inputs, ... }:

{
  # =====================================================================
  # Flatpak — декларативное управление приложениями.
  #
  # Используем nix-flatpak (gmodena/nix-flatpak) — NixOS-модуль,
  # который позволяет описывать Flatpak-приложения прямо в конфиге
  # и автоматически устанавливать/обновлять их.
  #
  # ID приложений берём с https://flathub.org
  # Список установленных: `flatpak list`
  # Поиск: `flatpak search <имя>`
  #
  # Статус сборок:
  #   - Официальные сборки от разработчиков приложений
  #     помечены как "official".
  #   - Community-сборки, поддерживаемые сообществом,
  #     помечены как "community".
  # =====================================================================

  imports = [
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ];

  services.flatpak = {
    enable = true;

    # === Приложения ===
    packages = [
      # --- Офис ---
      "org.libreoffice.LibreOffice"        # official: офисный пакет

      # --- Браузеры ---
      "com.brave.Browser"                  # official: браузер Brave
      "io.gitlab.librewolf-community"      # official: приватный браузер на базе Firefox
"org.chromium.Chromium"
      # --- Сеть и безопасность ---
      "org.qbittorrent.qBittorrent"        # official: торрент-клиент

      # --- Медиа ---
      "org.nickvision.tubeconverter"       # official: Parabolic (загрузка видео/аудио)


        "org.meshtastic.meshtasticd"        # Демон (серверная часть)
  "org.meshtastic.MeshtasticDesktop"  # Графический клиент



      # --- Утилиты ---
      "com.github.tchx84.Flatseal"         # official: GUI для управления правами Flatpak
    ];

    # === Репозитории ===
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];

    # === Обновление ===
    # Автоматическое обновление Flatpak-приложений раз в неделю.
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };

    # === Управление неуправляемыми приложениями ===
    # false — не удалять Flatpak-приложения, установленные вручную.
    uninstallUnmanaged = false;
  };

  # === GUI для установки Flatpak-приложений ===
  # Discover — родной магазин KDE с поддержкой Flatpak.
  environment.systemPackages = with pkgs; [
    kdePackages.discover
  ];
}
