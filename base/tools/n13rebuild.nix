{
  config,
  pkgs,
  ...
}: {
  # =====================================================================
  # n13rebuild — коммит, push и пересборка NixOS одной командой.
  #
  # РЕФАКТОРИНГ: скрипт лежит в base/tools (базовое ПО для всех), но
  # раньше был жёстко зашит под z13 (FLAKE_ATTR=".#z13"). Теперь flake-аттрибут
  # берётся из os.environ.HOSTNAME — совпадает с networking.hostName,
  # заданным устройством (devices/<n>/config.nix). Скрипт работает на любом
  # устройстве без правки конфига.
  #
  # ИЗМЕНЕНИЕ:
  # Раньше после nixos-rebuild switch принудительно перезапускались
  # dnscrypt-proxy, nfqws2, sing-box. Это вызывало race condition:
  # nfqws2 успевал привязаться к очереди NFQUEUE, но sing-box ещё
  # не создал TUN. Пакеты уходили в пустую очередь и терялись.
  # Итог: после n13rebuild интернет отваливался на несколько секунд,
  # иногда соединения не восстанавливались.
  #
  # Теперь перезапуск убран. Systemd сам решает, какие сервисы
  # перезапустить при смене конфигурации (RestartIfChanged или
  # автоматически при изменении unit-файла). Если конфиг не менялся —
  # сервисы не трогаются.
  #
  # Если нужно принудительно перезапустить — вручную:
  #   sudo systemctl restart nfqws2 sing-box
  # =====================================================================
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "n13rebuild" ''
      #!/usr/bin/env bash
      set -e

      REPO="$HOME/projects/nix-wrap/nix"
      # Flake-атрибут = имя хоста устройства (networking.hostName).
      # Позволяет одному скрипту обслуживать все машины (.#z13, .#pc, ...).
      FLAKE_ATTR=".#$HOSTNAME"
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

      echo ""
      echo "==> Готово."
      echo ""
      echo "Если интернет не работает — перезапустите сервисы вручную:"
      echo "  sudo systemctl restart sing-box"
      echo "  sleep 2"
      echo "  sudo systemctl restart nfqws2"
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
