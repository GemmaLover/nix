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
  #   6. sudo systemctl restart dnscrypt-proxy
  #   7. sudo systemctl restart sing-box
  #
  # ЗАЧЕМ ПЕРЕЗАПУСК СЕРВИСОВ:
  # - dnscrypt-proxy: после пересборки у него остаются старые сокеты
  #   и conntrack-записи. Если sing-box пересоздаёт TUN, старые
  #   соединения dnscrypt-proxy висят в SYN-SENT и DNS не работает.
  #   Рестарт сбрасывает сокеты и поднимает свежие DoH-сессии.
  # - sing-box: пересоздаёт TUN, пересобирает ip rule и таблицу 2022.
  #   Даже если systemd сам рестартует его при пересборке — явный
  #   рестарт гарантирует, что auto_route встал после nftables.
  # =====================================================================
  #
  # n13clear — очистка старых поколений NixOS и сборка мусора.
  #
  # Использование:
  #   n13clear           # удалить ВСЕ старые поколения (оставить текущее)
  #   n13clear 7         # удалить поколения старше 7 дней
  #   n13clear 30        # удалить поколения старше 30 дней
  #
  # Что делает:
  #   1. sudo nix-collect-garbage -d            ← system profile
  #      (или --delete-older-than Nd при указании аргумента)
  #   2. nix-collect-garbage -d                 ← user profile
  #      (то же самое, но без sudo)
  #   3. Обновляет записи systemd-boot:
  #      sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
  #      Это удаляет из меню загрузчика ссылки на удалённые поколения.
  #
  # ВАЖНО:
  # - После n13clear старые поколения в меню systemd-boot исчезнут.
  #   Откатиться (`nixos-rebuild switch --rollback`) можно только
  #   к текущему рабочему поколению — предыдущие стёрты.
  # - Если хотите сохранить недавние поколения на случай отката —
  #   используйте `n13clear 7` (оставит всё за последнюю неделю).
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

      # === Перезапуск зависимых сервисов ===
      for svc in dnscrypt-proxy sing-box; do
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

      # Аргумент: сколько дней хранить. По умолчанию — удалить всё старое.
      KEEP_DAYS="$1"

      if [ -n "$KEEP_DAYS" ]; then
        # Проверяем, что аргумент — число
        if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]]; then
          echo "Ошибка: аргумент должен быть числом (дни), например: n13clear 7" >&2
          exit 1
        fi
        SYS_ARG="--delete-older-than ''${KEEP_DAYS}d"
        USER_ARG="--delete-older-than ''${KEEP_DAYS}d"
        echo "==> Удаляем поколения старше $KEEP_DAYS дней"
      else
        # -d = --delete-old (удалить все старые поколения профиля)
        SYS_ARG="-d"
        USER_ARG="-d"
        echo "==> Удаляем ВСЕ старые поколения (останется только текущее)"
      fi

      echo "==> Сборка мусора системного профиля (sudo nix-collect-garbage $SYS_ARG)"
      sudo nix-collect-garbage $SYS_ARG

      echo "==> Сборка мусора пользовательского профиля (nix-collect-garbage $USER_ARG)"
      nix-collect-garbage $USER_ARG || true

      # Обновляем записи systemd-boot: убираем из меню ссылки
      # на удалённые поколения.
      echo "==> Обновление записей systemd-boot"
      if [ -x /nix/var/nix/profiles/system/bin/switch-to-configuration ]; then
        sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      else
        echo "    switch-to-configuration не найден — пропускаем"
      fi

      # Показываем, что осталось
      echo ""
      echo "==> Текущие поколения системы:"
      sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10

      echo ""
      echo "==> Готово."
    '')
  ];
}
