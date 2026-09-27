{
  config,
  lib,
  pkgs,
  ...
}: let
  # Версия blockcheckw.
  version = "0.12.0";

  # Архитектура системы.
  arch = "x86_64";

  # Хэш скачанного архива.
  # Для 0.9.4 был: sha256-zbPnL5M/0PEOpbULw8u9JTDUQDp9YeIEuVjCy7aTkDw=
  # Для 0.12.0 получим через lib.fakeHash (см. ниже).
  hash = lib.fakeHash;

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
  environment.systemPackages = [
    blockcheckw

    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      exec ${blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
