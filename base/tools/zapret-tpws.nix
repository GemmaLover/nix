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
  #   tpws — это stream-level прокси, часть оригинального zapret.
  # - tpws реализует SOCKS4/SOCKS5 и не требует nfqueue/nftables.
  # - sing-box направляет Brave на 127.0.0.1:3472 (zapret-out).
  # =====================================================================

  systemd.services.zapret-tpws = {
    description = "zapret (tpws) SOCKS proxy for DPI bypass";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.zapret}/bin/tpws \
          --socks \
          --port=3472 \
          --bind-addr=127.0.0.1 \
          --debug=1 \
          -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As
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
  #
  # Использование:
  #   zapret-find-strategy instagram.com
  #   zapret-find-strategy youtube.com --tls13
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
      systemctl cat zapret-tpws 2>/dev/null | grep -A3 "ExecStart" || echo "  unit не найден"
    '')
  ];
}
