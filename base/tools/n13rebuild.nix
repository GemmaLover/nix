{
  pkgs,
  ...
}: {
  # =====================================================================
  # n13rebuild — коммит, push и пересборка NixOS одной командой.
  #
  # Использование:
  #   n13rebuild "network: fix NAT rules"
  #   n13rebuild                 # сообщение по умолчанию: "update"
  #
  # Что делает:
  #   1. cd в ~/projects/nix-wrap/nix
  #   2. git add .
  #   3. git commit -m "$MSG"    (не падает, если коммитить нечего)
  #   4. git push
  #   5. sudo nixos-rebuild switch --flake .#z13
  #   6. sudo systemctl restart dnscrypt-proxy
  #   7. sudo systemctl restart byedpi
  #   8. sudo systemctl restart zapret-tpws
  #   9. sudo systemctl restart sing-box
  #
  # ЗАЧЕМ ПЕРЕЗАПУСК СЕРВИСОВ:
  # - dnscrypt-proxy: после пересборки остаются старые сокеты.
  #   Рестарт сбрасывает их и поднимает свежие DoH-сессии.
  # - byedpi: перечитывает hosts.txt и пересоздаёт SOCKS5-сокет.
  # - zapret-tpws: пересоздаёт SOCKS5-сокет tpws.
  # - sing-box: пересоздаёт TUN, пересобирает ip rule и таблицу 2022.
  #
  # Порядок важен: DNS → ByeDPI → zapret → sing-box.
  # =====================================================================
  #
  # n13clear — очистка старых поколений NixOS и сборка мусора.
  #
  # Использование:
  #   n13clear           # удалить ВСЕ старые поколения
  #   n13clear 7         # удалить поколения старше 7 дней
  #   n13clear 30        # удалить поколения старше 30 дней
  #
  # Что делает:
  #   1. sudo nix-collect-garbage -d (или --delete-older-than Nd)
  #   2. nix-collect-garbage -d (user profile)
  #   3. Обновляет записи systemd-boot (убирает удалённые поколения)
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
      # Каждый сервис проверяется на существование — если
      # не найден, шаг пропускается без ошибки.
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
