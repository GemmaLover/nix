{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # zapret2 — локальный SOCKS5-прокси для обхода DPI (tpws в socks mode).
  #
  # Архитектура:
  # ┌─────────────────────────────────────────────────────────────┐
  # │ tpws (zapret2) слушает 127.0.0.1:3472                       │
  # │ - реализует SOCKS4/SOCKS5                                   │
  # │ - применяет стратегии обхода DPI к TCP-соединениям          │
  # │ - работает автономно, без nfqueue и nftables                │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box направляет Brave на 127.0.0.1:3472 (zapret2-out)   │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - tpws — это stream-level прокси. Он не перехватывает трафик
  #   глобально, а только обрабатывает соединения, явно
  #   направленные на него через SOCKS.
  # - Стратегии задаются в extraOptions (флаги -d, -s, -r, -S и т.д.).
  # - В модуле nixpkgs опция называется extraOptions, а не extraArgs.
  # =====================================================================
  services.zapret2 = {
    enable = true;

    # tpws в режиме SOCKS-прокси на порту 3472.
    # --socks — включает SOCKS4/5 вместо прозрачного прокси.
    # --port=3472 — порт прослушивания.
    extraOptions = [
      "--socks"
      "--port=3472"
      "--debug=1"

      # --- Стратегии обхода DPI (базовый набор) ---
      # Подобраны как стартовые. Если что-то не работает —
      # используйте zapret2-find-strategy для подбора.
      #
      # -dN — disorder: отправка пакетов в обратном порядке
      # -sN+s — split: разбиение пакета в позиции N
      # -rN+s — split с повтором
      # -S — SYN-ACK desync
      # -aN — autore: автоматический подбор
      # -As — авто-стратегия для SNI
      "-d1"
      "-d3+s"
      "-s6+s"
      "-d9+s"
      "-s12+s"
      "-d15+s"
      "-s20+s"
      "-d25+s"
      "-s30+s"
      "-d35+s"
      "-r1+s"
      "-S"
      "-a1"
      "-As"
    ];
  };

  # =====================================================================
  # Скрипт zapret2-find-strategy — автоматический подбор стратегий.
  #
  # Использование:
  #   zapret2-find-strategy instagram.com
  #   zapret2-find-strategy youtube.com --tls13
  #
  # Что делает:
  #   1. Запускает blockcheck2.sh из состава zapret2.
  #   2. blockcheck2 перебирает стратегии для указанного домена.
  #   3. Выводит SUMMARY с найденными рабочими стратегиями.
  #   4. Показывает, какие параметры вставить в zapret2.nix.
  #
  # blockcheck2 — это shell-скрипт, входящий в состав zapret2.
  # Он тестирует TLS 1.2/1.3 и QUIC, перебирая комбинации
  # манипуляций с пакетами.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "zapret2-find-strategy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Использование: zapret2-find-strategy <domain> [--tls13] [--quic]"
        echo ""
        echo "Примеры:"
        echo "  zapret2-find-strategy instagram.com"
        echo "  zapret2-find-strategy youtube.com --tls13"
        echo "  zapret2-find-strategy discord.com --tls13 --quic"
        echo ""
        echo "Скрипт перебирает стратегии обхода DPI для указанного"
        echo "домена через blockcheck2 (входит в zapret2)."
        echo "В выводе смотрите секцию SUMMARY."
        exit 1
      fi

      DOMAIN="$1"
      shift

      # Ищем blockcheck2.sh в Nix store.
      BLOCKCHECK=$(find ${zapret2}/ -name "blockcheck2.sh" 2>/dev/null | head -1)

      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: blockcheck2.sh не найден в пакете zapret2." >&2
        echo "Проверьте, что zapret2 установлен: nix-shell -p zapret2" >&2
        exit 1
      fi

      echo "==> Запуск blockcheck2 для домена: $DOMAIN"
      echo "==> blockcheck2: $BLOCKCHECK"
      echo ""

      # blockcheck2 принимает DOMAIN первым аргументом.
      # Дополнительные флаги (--tls13, --quic) передаются дальше.
      # Требуется root для SO_MARK и nfqueue.
      sudo "$BLOCKCHECK" "$DOMAIN" "$@"
    '')

    # Утилита для просмотра текущего состояния tpws.
    (writeShellScriptBin "zapret2-status" ''
      #!/usr/bin/env bash
      echo "=== tpws (zapret2 SOCKS-прокси) ==="
      if systemctl is-active --quiet zapret2 2>/dev/null; then
        echo "Статус: активен"
        echo ""
        echo "Слушает:"
        sudo ss -tlnp | grep 3472 || echo "  порт 3472 не слушается"
      else
        echo "Статус: неактивен"
      fi

      echo ""
      echo "=== Стратегии (из systemd unit) ==="
      systemctl cat zapret2 2>/dev/null | grep -A5 "ExecStart" || \
        echo "  unit не найден"
    '')
  ];

  # =====================================================================
  # Автозапуск: tpws не требует nftables/nfqueue,
  # но нужен network-online.target.
  # =====================================================================
  systemd.services.zapret2 = {
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      WantedBy = [ "multi-user.target" ];
    };
  };
}
