{ pkgs ? import <nixpkgs> { } }:

pkgs.amnezia-vpn.overrideAttrs (finalAttrs: previousAttrs: rec {
  version = "5.0.3.0";

  src = pkgs.fetchFromGitHub {
    owner = "amnezia-vpn";
    repo = "amnezia-client";
    rev = "5.0.3.0";
    hash = "sha256-3D2GIpu5yMVQwMTwlyGvd/qHuKJB++4udt976ZxY5lw="; # хэш из nix hash to-sri
  };

  # Отключаем патчи, которые не подходят к новой версии.
  # Если после сборки какие-то функции не работают, можно вернуть
  # отдельные патчи, добавив их выборочно.
  patches = [ ];
})
