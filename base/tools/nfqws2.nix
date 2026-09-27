{
  config,
  lib,
  pkgs,
  ...
}: let
  ZAPRET_BASE = "/opt/zapret2";
  QNUM = "200";
  DESYNC_MARK = "0x40000000";

  # =====================================================================
  # СТРАТЕГИИ.
  #
  # В zapret2 функция disorder называется multidisorder.
  # Она требует параметр pos= (позиции для разбиения).
  # Без pos= nfqws2 падает с ошибкой "desync function does not exist".
  #
  # multisplit — просто разбивает пакет.
  # multidisorder — разбивает и отправляет фрагменты в обратном порядке.
  # =====================================================================

  # --- Стратегия для TLS (HTTPS через TCP/443) ---
  # multisplit: разбивает ClientHello после первого байта.
  # multidisorder: разбивает и отправляет фрагменты в обратном порядке.
  TLS_STRATEGY = [
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1"
    "--lua-desync=multidisorder:pos=1,sniext+1"
  ];

  # --- Стратегия для HTTP (TCP/80) ---
  HTTP_STRATEGY = [
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2"
  ];

  # --- Общие аргументы ---
  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
  ];

  ALL_ARGS = BASE_ARGS ++ TLS_STRATEGY ++ HTTP_STRATEGY;
in {
  # Симлинки на ресурсы zapret2.
  # Создаём с правами 0755, чтобы nfqws2 мог читать Lua-скрипты.
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  systemd.services.nfqws2 = {
    description = "nfqws2 (zapret2) DPI bypass daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "nftables.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.zapret2}/bin/nfqws2 " + lib.concatStringsSep " " ALL_ARGS;
      Restart = "on-failure";
      RestartSec = 5;

      # nfqws2 требует root для NFQUEUE и изменения пакетов.
      User = "root";
      Group = "root";

      # Безопасность (без PrivateTmp, чтобы не мешать доступу к /opt).
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ProtectHome = true;
      ReadWritePaths = [ "/run" "/var/log" ];

      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # =====================================================================
  # nftables: перехват трафика с mark 110 (от sing-box outbound zapret-out).
  #
  # Исключения:
  #   - DNS (порт 53) — не перехватываем.
  #   - Локальные адреса — не перехватываем.
  # =====================================================================
  networking.nftables.ruleset = ''
    table inet zapret_nfqws2 {
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        meta mark and ${DESYNC_MARK} != 0 return

        meta mark 110 udp dport 53 return
        meta mark 110 tcp dport 53 return
        meta mark 110 ip daddr 127.0.0.0/8 return
        meta mark 110 ip6 daddr ::1 return

        meta mark 110 tcp dport {80, 443} \
          ct original packets 1-6 queue num ${QNUM} bypass

        meta mark 110 udp dport 443 \
          ct original packets 1-6 queue num ${QNUM} bypass
      }

      chain prerouting {
        type filter hook prerouting priority -101; policy accept;
        meta mark and ${DESYNC_MARK} == ${DESYNC_MARK} return
      }
    }
  '';

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "nfqws2-status" ''
      #!/usr/bin/env bash
      echo "=== nfqws2 (zapret2) ==="
      systemctl is-active --quiet nfqws2 2>/dev/null && echo "Статус: активен" || echo "Статус: неактивен"
      echo ""
      echo "=== ExecStart ==="
      systemctl cat nfqws2 2>/dev/null | grep -A3 "ExecStart"
      echo ""
      echo "=== nftables ==="
      sudo nft list table inet zapret_nfqws2 2>/dev/null
    '')

    (writeShellScriptBin "nfqws2-find-strategy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Использование: nfqws2-find-strategy <domain>"
        exit 1
      fi

      DOMAIN="$1"
      BLOCKCHECK=$(find ${zapret2}/ -name "blockcheck2.sh" -type f 2>/dev/null | head -1)

      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: blockcheck2.sh не найден." >&2
        exit 1
      fi

      cd "$(dirname "$BLOCKCHECK")"
      echo "==> Запуск blockcheck2.sh для: $DOMAIN"
      sudo ./blockcheck2.sh "$DOMAIN"
    '')
  ];
}
