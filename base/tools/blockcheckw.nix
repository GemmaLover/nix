{
  config,
  lib,
  pkgs,
  ...
}: let
  version = "0.12.0";
  arch = "x86_64";
  hash = "sha256-uEqAi5xCyryIdZ6HqLj+Hi31b02ywqr1X4fKy4Zv4qk=";

  blockcheckw = pkgs.stdenv.mkDerivation {
    pname = "blockcheckw";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/rcd27/blockcheckw/releases/download/v${version}/blockcheckw-linux-${arch}.tar.gz";
      inherit hash;
    };
    unpackPhase = ''tar -xzf $src'';
    installPhase = ''
      mkdir -p $out/bin
      cp blockcheckw $out/bin/
      chmod +x $out/bin/blockcheckw
    '';
  };
in {
  # =====================================================================
  # blockcheckw — быстрый сканер стратегий DPI bypass (Rust).
  #
  # ВАЖНО:
  # - blockcheckw требует nfqws2 из состава zapret2.
  # - Симлинки /opt/zapret2/* → ${pkgs.zapret2}/share/zapret2/*
  #   создаются в base/tools/nfqws2.nix.
  # - Обёртка добавляет zapret2 в PATH и выставляет ZAPRET_BASE.
  #
  # Использование:
  #   sudo blockcheckw scan -d instagram.com
  #   sudo blockcheckw universal --domain-list /tmp/blocked.txt --sample 5
  #   sudo blockcheckw status --domain-list /tmp/blocked.txt
  # =====================================================================
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
