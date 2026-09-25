{ pkgs ? import <nixpkgs> { } }:

# Переопределяем версию amnezia-vpn на 5.0.3.0.
# Используем overrideAttrs, чтобы сохранить все зависимости
# и патчи из стандартного пакета nixpkgs.
pkgs.amnezia-vpn.overrideAttrs (finalAttrs: previousAttrs: rec {
  version = "5.0.3.0";

  src = pkgs.fetchFromGitHub {
    owner = "amnezia-vpn";
    repo = "amnezia-client";
    rev = "5.0.3.0";
    # Хэш получен командой:
    #   nix-prefetch-url --unpack \
    #     https://github.com/amnezia-vpn/amnezia-client/archive/refs/tags/5.0.3.0.tar.gz
    # Затем сконвертирован в SRI:
    #   nix hash to-sri --type sha256 <base32>
    hash = "sha256-3D2GIpu5yMVQwMTwlyGvd/qHuKJB++4udt976ZxY5lw=";
  };
})
