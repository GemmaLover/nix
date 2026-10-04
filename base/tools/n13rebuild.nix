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
  #
  # ИЗМЕНЕНИЕ (доработка): в самом начале скрипт выполняет `nix flake check`.
  # Это ловит ошибки eval (несуществующие опции, битые импорты, синтаксис)
  # ДО git commit/push и до sudo nixos-rebuild switch — раньше битый конфиг
  # коммитился, пушился и только потом падал на сборке, засоряя историю git.
  # При неуспешной проверке скрипт прерывается (set -e) и ничего не меняет.
  # Флаг --extra-experimental-features не нужен: nix-command/flakes включены
  # системно (base/system/nix-settings.nix).
  #
  # ИСПРАВЛЕНИЕ: `git add .` теперь ВЫПОЛНЯЕТСЯ ДО `nix flake check`.
  # Причина: flake видит только файлы, отслеживаемые git. Если добавить
  # новый файл (например, llm/dsh/local/commands.nix) и не сделать
  # `git add`, то `nix flake check` его НЕ увидит — проверка пройдёт
  # «вхолостую», а ошибки всплывут только на `nixos-rebuild switch`.
  # Если flake check падает — staged-файлы остаются в индексе, можно
  # поправить конфиг и перезапустить n13rebuild без потери работы.
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

      # --- Шаг 0: индексируем изменения, чтобы flake их увидел ------------
      # `nix flake check` работает с git-индексом, а не с рабочим деревом.
      # Без `git add .` новые (untracked) файлы для flake не существуют,
      # и проверка проходит «вхолостую». Индексируем ДО check — так flake
      # видит полное состояние дерева. Если check упадёт, файлы останутся
      # staged: коммита не будет, правки не потеряются.
      echo "==> git add ."
      git add .

      # --- Шаг 0.5: проверка конфигурации ДО коммита ----------------------
      # Проверяем индексированное состояние. Если eval падает — выходим
      # сразу: коммита, пуша и сборки не будет.
      echo "==> nix flake check (валидация конфига перед коммитом)"
      if ! nix flake check --no-build; then
        echo ""
        echo "ОШИБКА: 'nix flake check' не пройден — конфиг битый." >&2
        echo "Исправьте ошибки выше, затем повторите запуск." >&2
        echo "(Изменения уже в git-индексе — можно править и перезапускать.)" >&2
        exit 1
      fi

      echo "==> git commit -m \"$MSG\""
      if ! git diff --cached --quiet; then
        git commit -m "$MSG"
      else
        echo "    Нечего коммитить — пропускаем"
      fi

      echo "==> git push"
      git push

      # --- Шаг 1.5: dry-build ПОСЛЕ коммита --------------------------------
      # Теперь в рабочем дереве нет незакоммиченных правок, и nixos-rebuild
      # видит чистый git HEAD. dry-build проверяет сборку derivation'ов для
      # конкретного устройства (.#z13), ничего не применяя к системе.
      # Падение здесь = пуш уже сделан, но система НЕ переключена — история
      # git остаётся последовательной (каждый закоммиченный шаг проверен).
      echo "==> sudo nixos-rebuild dry-build --flake $FLAKE_ATTR"
      if ! sudo nixos-rebuild dry-build --flake "$FLAKE_ATTR"; then
        echo ""
        echo "ОШИБКА: dry-build не прошёл — коммит и push выполнены," >&2
        echo "но система НЕ переключена. Исправьте конфиг и повторите." >&2
        exit 1
      fi

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
