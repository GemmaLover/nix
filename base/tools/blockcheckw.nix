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

  # SRI-хэш архива blockcheckw-${version}.
  hash = "sha256-uEqAi5xCyryIdZ6HqLj+Hi31b02ywqr1X4fKy4Zv4qk=";

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
  # ПРОБЛЕМА С ПУТЯМИ:
  # nfqws2 ищет свои ресурсы по путям, захардкоженным в исходниках:
  #   $ZAPRET_BASE/lua/zapret-lib.lua
  #   $ZAPRET_BASE/lua/zapret-antidpi.lua
  #   $ZAPRET_BASE/files/fake/*.bin
  #   $ZAPRET_BASE/nfq2/nfqws2
  #
  # В NixOS эти файлы лежат в /nix/store/...-zapret2-.../share/zapret2/,
  # а /opt/zapret2 — пустой или отсутствует.
  #
  # РЕШЕНИЕ:
  # Создаём симлинки с ожидаемых путей (/opt/zapret2/*) на реальные
  # директории в Nix store. Тогда nfqws2 и blockcheckw работают
  # без патчей бинарника.
  #
  # УНИВЕРСАЛЬНОСТЬ:
  # Интерполяция ${pkgs.zapret2} вычисляется НА ЭТАПЕ СБОРКИ, поэтому
  # при каждом nixos-rebuild симлинки пересоздаются с актуальным
  # путём к текущей версии zapret2. Флаг "L+" в tmpfiles
  # пересоздаёт симлинк, не оставляя висящих ссылок.
  #
  # Использование:
  #   sudo blockcheckw scan -d instagram.com
  #   sudo blockcheckw universal --domain-list /tmp/blocked.txt --sample 5
  #   sudo blockcheckw status --domain-list /tmp/blocked.txt
  # =====================================================================

  # Симлинки на ресурсы zapret2.
  # "d" — создать каталог.
  # "L+" — создать/пересоздать симлинк.
  systemd.tmpfiles.rules = [
    # Корневая директория.
    "d /opt/zapret2 0755 root root -"

    # Lua-скрипты (zapret-lib.lua, zapret-antidpi.lua и т.д.)
    # — нужны nfqws2 для работы стратегий.
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"

    # Fake-блобы (фейковые TLS/HTTP-пакеты)
    # — используются стратегиями --dpi-desync=fake.
    "L+ /opt/zapret2/files - - - - ${pkgs.zapret2}/share/zapret2/files"

    # Директория nfq2 с бинарником nfqws2 и вспомогательными утилитами.
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  environment.systemPackages = [
    # Сам blockcheckw.
    blockcheckw

    # Обёртка:
    #  - добавляет zapret2 в PATH (для nfqws2 и других утилит);
    #  - выставляет ZAPRET_BASE на /opt/zapret2, чтобы blockcheckw
    #    использовал симлинки, а не искал ресурсы в других местах.
    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      export ZAPRET_BASE="/opt/zapret2"
      exec ${blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
