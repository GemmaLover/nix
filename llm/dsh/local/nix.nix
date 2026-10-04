# Константы и зависимости для локального DSH.
#
# DSH — это монорепо на pnpm, требует Node.js ≥ 22.19.
# nodejs-official (с nodejs.org) нужен, потому что нативный аддон
# node-addon-require-builtin не работает с Nix-сборкой Node.js.
#
# Через _module.args.dshLocalConfig экспортирует:
#   port      — порт web-интерфейса DSH (7718)
#   repoDir   — путь к клонированному репозиторию (~/llm/dsh-local)
#   repoUrl   — upstream DSH
#   nodejs    — официальный Node.js
#   pnpm      — пакетный менеджер
{ config, pkgs, lib, ... }:

let
  # Официальный Node.js с nodejs.org — совместим с нативным аддоном
  # node-addon-require-builtin, который не работает с Nix-сборкой Node.js.
  nodejs-official = pkgs.callPackage ../../../pkgs/nodejs-official { };
in
{
  _module.args.dshLocalConfig = {
    port = 7718;
    repoDir = "${config.home.homeDirectory}/llm/dsh-local";
    repoUrl = "https://github.com/deepseek-ai/deepseek-harness.git";
    nodejs = nodejs-official;
    inherit (pkgs) pnpm;
  };
}
