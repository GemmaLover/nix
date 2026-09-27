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

  # SRI-хэш скачанного архива.
  # Получен через сборку с lib.fakeHash:
  #   specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  #      got:    sha256-zbPnL5M/0PEOpbULw8u9JTDUQDp9YeIEuVjCy7aTkDw=
  hash = "sha256-zbPnL5M/0PEOpbULw8u9JTDUQDp9YeIEuVjCy7aTkDw=";

  # Собственно пакет blockcheckw.
  blockcheckw = pkgs.stdenv.mkDerivation {
    pname = "blockcheckw";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/rcd27/blockcheckw/releases/download/v${version}/blockcheckw-linux-${arch}.tar.gz";
      inherit hash;
    };

    # Распаковываем архив.
    unpackPhase = ''
      tar -xzf $src
    '';

    # Копируем бинарник в $out/bin.
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
  #   Добавляем zapret2 в PATH через обёртку.
  # - Бинарник скачивается из GitHub Releases и проверяется по SHA256.
  # - Устанавливается в /run/current-system/sw/bin/blockcheckw.
  #
  # Использование:
  #   sudo blockcheckw scan -d instagram.com
  #   sudo blockcheckw scan -d youtube.com --tls13
  # =====================================================================
  environment.systemPackages = [
    # Сам blockcheckw (бинарник из релиза).
    blockcheckw

    # Обёртка, которая добавляет zapret2 в PATH (для nfqws2).
    # Без неё blockcheckw не найдёт nfqws2 и упадёт.
    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      exec ${blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
