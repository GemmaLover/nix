{
  config,
  lib,
  pkgs,
  ...
}: let
  # Версия blockcheckw.
  version = "0.12.0";

  # Архитектура системы (x86_64 для вашего z13).
  arch = "x86_64";

  # Фиктивный хэш — Nix при сборке покажет реальный в строке "got:".
  # После первой ошибки замените lib.fakeHash на:
  #   hash = "sha256-<значение из got>";
  hash = lib.fakeHash;

  # Пакет blockcheckw из релиза на GitHub.
  blockcheckw = pkgs.stdenv.mkDerivation {
    pname = "blockcheckw";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/rcd27/blockcheckw/releases/download/v${version}/blockcheckw-linux-${arch}.tar.gz";
      inherit hash;
    };

    unpackPhase = ''
      tar -xzf $src
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp blockcheckw $out/bin/
      chmod +x $out/bin/blockcheckw
    '';
  };
in {
  # =====================================================================
  # blockcheckw — быстрый сканер стратегий DPI bypass (Rust).
  # =====================================================================

  # Симлинк /opt/zapret2/nfq2/nfqws2 → текущий nfqws2 из pkgs.zapret2.
  # Интерполяция ${pkgs.zapret2} вычисляется на этапе сборки,
  # поэтому при каждом nixos-rebuild симлинк пересоздаётся
  # с актуальным путём. Флаг "L+" пересоздаёт симлинк.
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  environment.systemPackages = [
    blockcheckw
    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      export ZAPRET_BASE="/opt/zapret2"
      exec ${blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
