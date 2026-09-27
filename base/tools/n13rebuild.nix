{
  pkgs,
  ...
}: {
  # =====================================================================
  # n13rebuild — коммит, push и пересборка NixOS одной командой.
  #
  # Использование:
  #   n13rebuild "network: fix NAT rules"
  #   n13rebuild                 # если сообщение не указано — "update"
  #
  # Что делает:
  #   1. cd в ~/projects/nix-wrap/nix
  #   2. git add .
  #   3. git commit -m "$MSG"    (не падает, если коммитить нечего)
  #   4. git push
  #   5. sudo nixos-rebuild switch --flake .#z13
  # =====================================================================
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "n13rebuild" ''
      #!/usr/bin/env bash
      set -e

      REPO="$HOME/projects/nix-wrap/nix"
      FLAKE_ATTR=".#z13"
      MSG="''${1:-update}"

      if [ ! -d "$REPO" ]; then
        echo "Ошибка: директория $REPO не найдена" >&2
        exit 1
      fi

      cd "$REPO"

      echo "==> git add ."
      git add .

      echo "==> git commit -m \"$MSG\""
      if ! git diff --cached --quiet; then
        git commit -m "$MSG"
      else
        echo "    Нечего коммитить — пропускаем"
      fi

      echo "==> git push"
      git push

      echo "==> sudo nixos-rebuild switch --flake $FLAKE_ATTR"
      sudo nixos-rebuild switch --flake "$FLAKE_ATTR"

      echo "==> Готово."
    '')
  ];
}
