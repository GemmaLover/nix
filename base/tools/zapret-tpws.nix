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
  # Скрипт zapret-find-strategy — поиск стратегий для tpws.
  # Использует blockcheck.sh из состава zapret.
  # =====================================================================
  environment.systemPackages = with pkgs; [
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

      BLOCKCHECK=$(find ${zapret}/ -name "blockcheck.sh" 2>/dev/null | head -1)
      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: blockcheck.sh не найден в пакете zapret." >&2
        exit 1
      fi

      echo "==> Запуск blockcheck для домена: $DOMAIN"
      sudo "$BLOCKCHECK" "$DOMAIN" "$@"
    '')

    (writeShellScriptBin "zapret-status" ''
      #!/usr/bin/env bash
      echo "=== tpws (zapret SOCKS-прокси) ==="
      if systemctl is-active --quiet zapret-tpws 2>/dev/null; then
        echo "Статус: активен"
        sudo ss -tlnp | grep 3472 || echo "  порт 3472 не слушается"
      else
        echo "Статус: неактивен"
      fi
      echo ""
      echo "=== ExecStart ==="
      systemctl cat zapret-tpws 2>/dev/null | grep -A5 "ExecStart" || echo "  unit не найден"
    '')
  ];
}
