{
  description = "NixOS multi-device configuration for z13, PC, and ASUS laptop";

  inputs = {
    # Актуальный стабильный релиз NixOS 26.05 «Yarara».
    # Обновления безопасности до 2026-12-31.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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
  };

  outputs = { self, nixpkgs, home-manager, disko, ... }@inputs: {
    nixosConfigurations = {
      # === Устройство: ASUS Z13 ===
      z13 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./devices/z13/config.nix
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.lexi = import ./devices/z13/home.nix;
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
