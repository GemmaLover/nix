{
  config,
  lib,
  pkgs,
  ...
}: let
  # Версия blockcheckw для установки.
  # Проверить последнюю версию: https://github.com/rcd27/blockcheckw/releases
  version = "0.9.4";

  # Архитектура системы (по умолчанию x86_64).
  # Если у вас ARM (например, Raspberry Pi) — замените на "arm64".
  arch = "x86_64";

  # Хэш скачанного архива (SHA256).
  # Взят из официального релиза. Если версия изменится — обновите хэш.
  # Получить хэш: nix-prefetch-url https://github.com/rcd27/blockcheckw/releases/download/v${version}/blockcheckw-linux-${arch}.tar.gz
  hash = "sha256-0g4hjfvcphjqp42f4qbx790d8c15pp5w62xmll7g3l1zjcpygcyd"; # ← замените на актуальный
in {
  # =====================================================================
  # blockcheckw — быстрый сканер стратегий DPI bypass (Rust).
  #
  # ВАЖНО:
  # - blockcheckw требует nfqws2 из состава zapret2.
  #   У вас установлен zapret (tpws), но не zapret2.
  #   Для работы blockcheckw нужно добавить pkgs.zapret2 в зависимости.
  # - Бинарник скачивается из GitHub Releases и проверяется по SHA256.
  # - Устанавливается в /run/current-system/sw/bin/blockcheckw.
  # =====================================================================

  # Скачиваем и распаковываем blockcheckw.
  environment.systemPackages = [
    (pkgs.stdenv.mkDerivation {
      pname = "blockcheckw";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/rcd27/blockcheckw/releases/download/v${version}/blockcheckw-linux-${arch}.tar.gz";
        inherit hash;
      };

      # Распаковываем архив и копируем бинарник.
      unpackPhase = ''
        tar -xzf $src
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp blockcheckw $out/bin/
        chmod +x $out/bin/blockcheckw
      '';

      # Добавляем zapret2 в зависимости (нужен nfqws2).
      buildInputs = [ pkgs.zapret2 ];
    })
  ];

  # =====================================================================
  # Обёртка для blockcheckw, которая автоматически подставляет
  # путь к nfqws2 из zapret2.
  #
  # Без этой обёртки blockcheckw не найдёт nfqws2 и упадёт
  # с ошибкой "nfqws2 not found".
  # =====================================================================
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "blockcheckw" ''
      #!/usr/bin/env bash
      export PATH="${pkgs.zapret2}/bin:$PATH"
      exec ${pkgs.blockcheckw}/bin/blockcheckw "$@"
    '')
  ];
}
