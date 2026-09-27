{
  config,
  lib,
  pkgs,
  ...
}: let
  # Версия blockcheckw.
  # При обновлении: поменять version + получить новый hash через lib.fakeHash.
  version = "0.12.0";

  # Архитектура системы (x86_64 для вашего z13).
  arch = "x86_64";

  # SRI-хэш архива blockcheckw-${version}.
  # Значение получено через сборку с lib.fakeHash.
  hash = "sha256-ЗАМЕНИТЕ_НА_РЕАЛЬНЫЙ_ХЭШ_ОТ_0.12.0=";

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
  #
  # ПРО УНИВЕРСАЛЬНОСТЬ:
  # blockcheckw ищет nfqws2 по пути $ZAPRET_BASE/nfq2/nfqws2
  # (по умолчанию /opt/zapret2/nfq2/nfqws2). В NixOS nfqws2 лежит
  # в /nix/store/.../bin/nfqws2, поэтому мы создаём симлинк.
  #
  # Симлинк создаётся через systemd.tmpfiles.rules с интерполяцией
  # ${pkgs.zapret2}. Интерполяция вычисляется НА ЭТАПЕ СБОРКИ,
  # поэтому при каждом nixos-rebuild симлинк пересоздаётся
  # с актуальным путём к текущей версии zapret2.
  #
  # Флаг "L+" в tmpfiles означает "создать или ПЕРЕсоздать симлинк",
  # поэтому при обновлении zapret2 старый симлинк не останется
  # висеть на удалённый из store путь.
  # =====================================================================

  # Создаём /opt/zapret2/nfq2/nfqws2 → текущий nfqws2 из pkgs.zapret2.
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  environment.systemPackages = [
    # Сам blockcheckw.
    blockcheckw

    # Обёртка:
    #  - добавляет zapret2 в PATH (для nfqws2 и других утилит);
    #  - выставляет ZAPRET_BASE на /opt/zapret2, чтобы blockcheckw
    #    использовал симлинк, а не искал nfqws2 в других местах.
    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      export ZAPRET_BASE="/opt/zapret2"
      exec ${blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
