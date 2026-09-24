{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "z13-uninstall" ''
      #!/usr/bin/env bash
      set -euo pipefail

      # === Деинсталлятор Z13-утилит ===
      # В NixOS пакеты не «устанавливаются» в традиционном смысле —
      # они являются частью поколения системы. Чтобы убрать их:
      #
      # 1. Удалите импорт z13-tools.nix из devices/z13/config.nix.
      # 2. Выполните nixos-rebuild switch.
      #
      # Этот скрипт лишь напоминает шаги и проверяет текущее состояние.

      echo "=== Z13 Uninstall Helper ==="
      echo ""
      echo "Текущее поколение системы:"
      readlink -f /run/current-system
      echo ""
      echo "Чтобы убрать Z13-утилиты:"
      echo "  1. Откройте devices/z13/config.nix"
      echo "  2. Закомментируйте или удалите строку:"
      echo "       ../../devices/z13/specific/z13-tools.nix"
      echo "  3. Выполните: sudo nixos-rebuild switch --flake .#z13"
      echo ""
      echo "Если нужно откатиться на предыдущее поколение:"
      echo "  sudo nixos-rebuild switch --rollback"
      echo ""
      echo "Проверка активных сервисов Z13:"
      systemctl --user list-units --all 'z13*' 2>/dev/null || true
    '')
  ];
}
