{
  description = "NixOS multi-device configuration for z13, PC, and ASUS laptop";

  inputs = {
    # Актуальный стабильный релиз NixOS 26.05 «Yarara».
    # Обновления безопасности до 2026-12-31.
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";

    # Home Manager — декларативное управление пользовательскими конфигами.
    # Версия release-26.05 соответствует nixpkgs 26.05.
    home-manager = {
      # url = "github:nix-community/home-manager/release-26.05";
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disko — декларативная разметка дисков с LUKS.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # plasma-manager — декларативное управление настройками KDE Plasma.
    # Нужен для настройки PowerDevil (авто-переключение профилей
    # при смене питания), темы, раскладки и т.д.
    # У проекта нет веток release-XX.XX — используется trunk (Plasma 6).
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Ядра CachyOS (LTO, BORE, LTS и т.д.) с собственным бинарным кэшем.
#      nix-cachyos-kernel = {
#        url = "github:xddxdd/nix-cachyos-kernel/release";
#        inputs.nixpkgs.follows = "nixpkgs";
#      };


 # CachyOS-ядра с патчами (BORE, LTO, zen4-оптимизация) и бинарным кэшем.
  # release-ветка — стабильные ядра, синхронизированные с nixpkgs.
  nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  # ВАЖНО: НЕ ставим inputs.nixpkgs.follows = "nixpkgs" — иначе версия
  # ядра будет зависеть от вашего nixpkgs и может «уплыть» с 7.2.8
  # на что-то другое. pinned-оверлей использует nixpkgs самого flake.
  };

  outputs = {
  self,
  nixpkgs,
  home-manager,
  disko,
  plasma-manager,
   nix-cachyos-kernel,
  ... }@inputs:
let
  # Фабрика нод nixosConfigurations (см. lib/mkSystem.nix):
  # подставляет disko, home-manager, plasma-manager, опции kda.opts
  # и диспетчеры осей ui/ и profiles/ — устройство объявляет только
  # свои оси в devices/<name>/config.nix.
  mkSystem = import ./lib/mkSystem.nix {
    inherit inputs nixpkgs home-manager disko plasma-manager;
  };
in {
    nixosConfigurations = {
      # === Устройство: ASUS Z13 ===
      z13 = mkSystem "z13" {
        deviceModule = ./devices/z13/config.nix;
        # Home-модули пользователя lexi (пустой список => HM не подключается).
        userHome = user: [ ./devices/z13/home.nix ];
      };

      # === Устройство: PC (AMD CPU + NVIDIA GPU) ===
      # pc = mkSystem "pc" {
      #   deviceModule = ./devices/pc/config.nix;
      #   userHome = user: [ ./devices/pc/home.nix ];
      # };

      # === Устройство: ASUS 5304UV (Intel) ===
      # asus5304uv = mkSystem "asus5304uv" {
      #   deviceModule = ./devices/asus5304uv/config.nix;
      #   userHome = user: [ ./devices/asus5304uv/home.nix ];
      # };
    };
  };
}
