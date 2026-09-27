{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # zapret (tpws) — локальный SOCKS5-прокси для обхода DPI.
  #
  # ВАЖНО:
  # - Используется пакет pkgs.zapret, а НЕ pkgs.zapret2.
  #   В zapret2 нет tpws, только nfqws2 (NFQUEUE).
  # - tpws реализует SOCKS4/SOCKS5 и не требует nfqueue/nftables.
  # - sing-box направляет Brave на 127.0.0.1:3472 (zapret-out).
  #
  # - КЛЮЧЕВОЕ ОТЛИЧИЕ ОТ nfqws:
  #   tpws принимает ТОЛЬКО длинные опции:
  #     --split-pos=N, --disorder, --tlsrec=marker+N, --oob
  #   Короткие флаги (-d1, -s6+s, -r1+s) — это синтаксис nfqws.
  #   Они НЕ работают с tpws и вызывают status=1/FAILURE.
  #
  # - ПОИСК СТРАТЕГИЙ:
  #   Скрипт zapret-find-strategy запускает blockcheck
  #   (бинарник без расширения .sh) из пакета zapret.
  #   Скрипт zapret-find-v2 запускает blockcheck2.sh
  #   из пакета zapret2 — он умеет работать с Lua-стратегиями
  #   и находит более сложные комбинации.
  # =====================================================================

  systemd.services.zapret-tpws = {
    description = "zapret (tpws) SOCKS proxy for DPI bypass";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";

      # tpws в режиме SOCKS-прокси.
      # Стратегии: split-pos=2 (разбиение ClientHello после 2 байт),
      # disorder (отправка фрагментов в обратном порядке),
      # tlsrec=sni (разбиение TLS-записи на уровне SNI).
      ExecStart = ''
        ${pkgs.zapret}/bin/tpws \
          --socks \
          --port=3472 \
          --bind-addr=127.0.0.1 \
          --debug=1 \
          --filter-tcp=443 \
          --split-pos=2 \
          --disorder \
          --tlsrec=sni
      '';

      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/run" ];
      StandardOutput = "journal";
      StandardError = "journal";
      RestartIfChanged = true;
    };
  };

  # =====================================================================
  # Скрипты для поиска стратегий и просмотра статуса.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    # --- zapret-find-strategy: blockcheck из пакета zapret ---
    # Использование:
    #   sudo zapret-find-strategy instagram.com
    (writeShellScriptBin "zapret-find-strategy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Использование: zapret-find-strategy <domain> [--tls13] [--quic]"
        echo "Пример: zapret-find-strategy instagram.com"
        exit 1
      fi

      DOMAIN="$1"
      shift

      BLOCKCHECK=$(find ${zapret}/ -name "blockcheck" -type f 2>/dev/null | head -1)
      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: бинарник blockcheck не найден в пакете zapret." >&2
        exit 1
      fi

      echo "==> Запуск blockcheck для домена: $DOMAIN"
      sudo "$BLOCKCHECK" "$DOMAIN" "$@"
    '')

    # --- zapret-find-v2: blockcheck2.sh из пакета zapret2 ---
    #
    # Использование:
    #   sudo zapret-find-v2 instagram.com
    #   sudo zapret-find-v2 instagram.com --stop-services
    #
    # Отличия от zapret-find-strategy:
    #   - использует blockcheck2.sh (умеет Lua-стратегии);
    #   - автоматически находит скрипт в пакете zapret2;
    #   - с флагом --stop-services останавливает zapret-tpws
    #     и byedpi на время теста и возвращает после.
    (writeShellScriptBin "zapret-find-v2" ''
      #!/usr/bin/env bash
      set -euo pipefail

      STOP_SERVICES=0
      DOMAIN=""

      # Парсим аргументы.
      for arg in "$@"; do
        case "$arg" in
          --stop-services)
            STOP_SERVICES=1
            ;;
          -h|--help)
            echo "Использование: zapret-find-v2 <domain> [--stop-services]"
            echo ""
            echo "Аргументы:"
            echo "  <domain>          Домен для тестирования (обязательно)"
            echo "  --stop-services   Остановить zapret-tpws и byedpi на время теста"
            echo ""
            echo "Примеры:"
            echo "  sudo zapret-find-v2 instagram.com"
            echo "  sudo zapret-find-v2 youtube.com --stop-services"
            exit 0
            ;;
          -*)
            echo "Неизвестный флаг: $arg" >&2
            exit 1
            ;;
          *)
            if [ -z "$DOMAIN" ]; then
              DOMAIN="$arg"
            fi
            ;;
        esac
      done

      if [ -z "$DOMAIN" ]; then
        echo "Ошибка: укажите домен." >&2
        echo "Использование: zapret-find-v2 <domain> [--stop-services]" >&2
        exit 1
      fi

      # Ищем blockcheck2.sh в пакете zapret2.
      BLOCKCHECK=$(find ${zapret2}/ -name "blockcheck2.sh" -type f 2>/dev/null | head -1)
      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: blockcheck2.sh не найден в пакете zapret2." >&2
        echo "Проверьте, что zapret2 установлен:" >&2
        echo "  nix-shell -p zapret2 --command 'find \$(dirname \$(which nfqws2))/.. -name blockcheck2.sh'" >&2
        exit 1
      fi

      BLOCKCHECK_DIR=$(dirname "$BLOCKCHECK")

      # Останавливаем сервисы, если попросили.
      if [ "$STOP_SERVICES" -eq 1 ]; then
        echo "==> Останавливаю zapret-tpws и byedpi на время теста"
        sudo systemctl stop zapret-tpws 2>/dev/null || true
        sudo systemctl stop byedpi 2>/dev/null || true
      fi

      # Запускаем blockcheck2.sh из его директории.
      # Скрипт использует относительные пути к blockcheck2.d/ и common/,
      # поэтому cd обязателен.
      echo "==> Запуск blockcheck2.sh для домена: $DOMAIN"
      echo "==> Директория: $BLOCKCHECK_DIR"
      echo ""

      cd "$BLOCKCHECK_DIR"
      sudo ./blockcheck2.sh "$DOMAIN"
      EXIT_CODE=$?

      # Возвращаем сервисы, если останавливали.
      if [ "$STOP_SERVICES" -eq 1 ]; then
        echo ""
        echo "==> Возвращаю zapret-tpws и byedpi"
        sudo systemctl start byedpi 2>/dev/null || true
        sudo systemctl start zapret-tpws 2>/dev/null || true
      fi

      exit $EXIT_CODE
    '')

    # --- zapret-status: показать текущий статус tpws ---
    (writeShellScriptBin "zapret-status" ''
      #!/usr/bin/env bash
      echo "=== tpws (zapret SOCKS-прокси) ==="
      if systemctl is-active --quiet zapret-tpws 2>/dev/null; then
        echo "Статус: активен"
        echo ""
        echo "Слушает:"
        sudo ss -tlnp | grep 3472 || echo "  порт 3472 не слушается"
      else
        echo "Статус: неактивен"
      fi
      echo ""
      echo "=== Стратегии (из systemd unit) ==="
      systemctl cat zapret-tpws 2>/dev/null | grep -A5 "ExecStart" || \
        echo "  unit не найден"
    '')
  ];
}
