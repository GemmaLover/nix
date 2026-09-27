{
  pkgs,
  ...
}: {
  # =====================================================================
  # n13rebuild — коммит, push и пересборка NixOS одной командой.
  #
  # Что делает:
  #   1. git add .
  #   2. git commit -m "$MSG"
  #   3. git push
  #   4. sudo nixos-rebuild switch --flake .#z13
  #   5. Перезапуск зависимых сервисов:
  #      dnscrypt-proxy → byedpi → zapret-tpws → sing-box
  #
  # n13clear — очистка старых поколений и сборка мусора.
  #   n13clear       — удалить ВСЕ старые поколения
  #   n13clear 7     — удалить старше 7 дней
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

      # Порядок: DNS → ByeDPI → zapret-tpws → sing-box.
      for svc in dnscrypt-proxy byedpi zapret-tpws sing-box; do
        if systemctl list-unit-files --quiet "$svc.service" >/dev/null 2>&1 \
           && systemctl cat "$svc.service" >/dev/null 2>&1; then
          echo "==> sudo systemctl restart $svc"
          sudo systemctl restart "$svc" || \
            echo "    Предупреждение: не удалось перезапустить $svc"
        else
          echo "==> $svc.service не найден — пропускаем"
        fi
      done

      echo "==> Готово."
    '')

    (pkgs.writeShellScriptBin "n13clear" ''
      #!/usr/bin/env bash
      set -e

      KEEP_DAYS="$1"

      if [ -n "$KEEP_DAYS" ]; then
        if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]]; then
          echo "Ошибка: аргумент должен быть числом (дни), например: n13clear 7" >&2
          exit 1
        fi
        SYS_ARG="--delete-older-than ''${KEEP_DAYS}d"
        USER_ARG="--delete-older-than ''${KEEP_DAYS}d"
        echo "==> Удаляем поколения старше $KEEP_DAYS дней"
      else
        SYS_ARG="-d"
        USER_ARG="-d"
        echo "==> Удаляем ВСЕ старые поколения (останется только текущее)"
      fi

      echo "==> Сборка мусора системного профиля (sudo nix-collect-garbage $SYS_ARG)"
      sudo nix-collect-garbage $SYS_ARG

      echo "==> Сборка мусора пользовательского профиля (nix-collect-garbage $USER_ARG)"
      nix-collect-garbage $USER_ARG || true

      echo "==> Обновление записей systemd-boot"
      if [ -x /nix/var/nix/profiles/system/bin/switch-to-configuration ]; then
        sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      else
        echo "    switch-to-configuration не найден — пропускаем"
      fi

      echo ""
      echo "==> Текущие поколения системы:"
      sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10

      echo ""
      echo "==> Готово."
    '')
  ];
}
