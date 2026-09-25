{
  description = "NixOS multi-device configuration for z13, PC, and ASUS laptop";

  inputs = {
    # Актуальный стабильный релиз NixOS 26.05 «Yarara».
    # Обновления безопасности до 2026-12-31.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

#     nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager — декларативное управление пользовательскими конфигами.
    # Версия release-26.05 соответствует nixpkgs 26.05.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
  };

  outputs = { self, nixpkgs, home-manager, disko, plasma-manager, ... }@inputs: {
    nixosConfigurations = {
      # === Устройство: ASUS Z13 ===
      z13 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./devices/z13/config.nix
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.lexi = {
              imports = [
                # Модуль plasma-manager для декларативной настройки KDE.
                # В новых версиях plasma-manager путь homeManagerModules
                # переименован в homeModules.
                plasma-manager.homeModules.plasma-manager
                # Основной конфиг пользователя lexi.
                ./devices/z13/home.nix
              ];
            };
          }
        ];
      };

      # === Устройство: PC (AMD CPU + NVIDIA GPU) ===
      # pc = nixpkgs.lib.nixosSystem {
      #   system = "x86_64-linux";
      #   modules = [ ./devices/pc/config.nix ];
      # };

      # === Устройство: ASUS 5304UV (Intel) ===
      # asus5304uv = nixpkgs.lib.nixosSystem {
      #   system = "x86_64-linux";
      #   modules = [ ./devices/asus5304uv/config.nix ];
      # };
    };
  };
}
