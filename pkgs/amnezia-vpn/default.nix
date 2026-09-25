{ pkgs ? import <nixpkgs> { } }:

pkgs.amnezia-vpn.overrideAttrs (finalAttrs: previousAttrs: rec {
  version = "5.0.3.0";

  src = pkgs.fetchFromGitHub {
    owner = "amnezia-vpn";
    repo = "amnezia-client";
    rev = "5.0.3.0";
    hash = "sha256-3D2GIpu5yMVQwMTwlyGvd/qHuKJB++4udt976ZxY5lw=";
  };

  # Патчи из nixpkgs не подходят к исходникам 5.0.3.0.
  # Отключаем и список patches, и postPatch, где они применяются.
  patches = [ ];
  postPatch = "";
})
