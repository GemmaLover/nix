{
  config,
  lib,
  pkgs,
  ...
}: let
  # =====================================================================
  # КОНСТАНТЫ
  # =====================================================================
  ZAPRET_BASE = "/opt/zapret2";
  QNUM = "200";
  DESYNC_MARK = "0x40000000";

  # =====================================================================
  # СТРАТЕГИИ ОБХОДА DPI
  #
  # УПРОЩЕНО: только multisplit:pos=1 для TLS.
  # Убран multisplit:pos=sniext+1 — он создавал больше сегментов,
  # что увеличивало вероятность превышения MTU при отправке.
  #
  # multisplit:pos=1 — разбивает ClientHello после первого байта.
  # Этого достаточно для обхода большинства DPI: TLS record header
  # (0x16 0x03 ...) разрывается, и DPI не может определить протокол.
  # =====================================================================

  TLS_STRATEGY = [
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1"
  ];

  HTTP_STRATEGY = [
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2"
  ];

  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
  ];

  ALL_ARGS = BASE_ARGS ++ TLS_STRATEGY ++ HTTP_STRATEGY;
in {
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
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ProtectHome = true;
      ReadWritePaths = [ "/run" "/var/log" ];
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # =====================================================================
  # NFTABLES: ПЕРЕХВАТ ТРАФИКА С MARK 110
  #
  # Пропускаем ВЕСЬ IPv6 (meta nfproto ipv6 return) — именно IPv6-пакеты
  # вызывали "Message too long" (1480 + 40 = 1520 > 1500).
  # =====================================================================
  networking.nftables.ruleset = ''
    table inet zapret_nfqws2 {
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        meta mark and ${DESYNC_MARK} != 0 return

        meta mark 110 udp dport 53 return
        meta mark 110 tcp dport 53 return
        meta mark 110 ip daddr 127.0.0.0/8 return

        meta mark 110 meta nfproto ipv6 return

        meta mark 110 meta nfproto ipv4 tcp dport {80, 443} \
          ct original packets 1-6 queue num ${QNUM} bypass

        meta mark 110 meta nfproto ipv4 udp dport 443 \
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
      if systemctl is-active --quiet nfqws2 2>/dev/null; then
        echo "Статус: активен"
      else
        echo "Статус: неактивен"
      fi
      echo ""
      echo "=== ExecStart ==="
      systemctl cat nfqws2 2>/dev/null | grep -A3 "ExecStart" || \
        echo "  unit не найден"
      echo ""
      echo "=== nftables (таблица zapret_nfqws2) ==="
      sudo nft list table inet zapret_nfqws2 2>/dev/null || \
        echo "  таблица не найдена"
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
        echo "Ошибка: blockcheck2.sh не найден в пакете zapret2." >&2
        exit 1
      fi

      cd "$(dirname "$BLOCKCHECK")"
      echo "==> Запуск blockcheck2.sh для домена: $DOMAIN"
      echo "==> Директория: $(pwd)"
      echo ""
      sudo ./blockcheck2.sh "$DOMAIN"
    '')
  ];
}
