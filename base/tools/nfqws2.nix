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
  # СТРАТЕГИЯ (упрощённая, БЕЗ GoldDopi)
  #
  # ОТКАЗ ОТ GOLDDOPI:
  # Полная стратегия GoldDopi с fake:blob=...:repeats=4 и
  # multidisorder на 7 позиций вызывала "Message too long" на каждом
  # пакете и замедляла YouTube. Простая multisplit работала лучше.
  #
  # Все blobs и lists оставлены в репозитории — пригодятся,
  # если позже понадобится точечная стратегия для X.com/Discord.
  # =====================================================================

  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--filter-l3=ipv4"
  ];

  STRATEGY = [
    # === TCP/443 (TLS) ===
    # multisplit:pos=1 — после TLS record header
    # multisplit:pos=sniext+1 — сразу после расширения SNI
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1,sniext+1"
    "--new"

    # === TCP/80 (HTTP) ===
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2,host+2"
  ];

  ALL_ARGS = BASE_ARGS ++ STRATEGY;
in {
  # =====================================================================
  # СИМЛИНКИ НА РЕСУРСЫ
  # =====================================================================
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"

    # Blobs и lists оставлены для будущих стратегий (X.com/Discord)
    "L+ /opt/zapret2/blobs - - - - ${./nfqws2/files/blobs}"
    "L+ /opt/zapret2/lists - - - - ${./nfqws2/files/lists}"
  ];

  # =====================================================================
  # SYSTEMD-СЕРВИС NFQWS2
  # =====================================================================
  systemd.services.nfqws2 = {
    description = "nfqws2 (zapret2) DPI bypass daemon";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "nftables.service"
      "sing-box.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "sing-box.service" ];

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
  # NFTABLES
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

  # =====================================================================
  # УТИЛИТЫ
  # =====================================================================
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "nfqws2-status" ''
      #!/usr/bin/env bash
      echo "=== nfqws2 (zapret2) ==="
      systemctl is-active --quiet nfqws2 2>/dev/null && echo "Статус: активен" || echo "Статус: неактивен"
      echo ""
      echo "=== Профили ==="
      sudo journalctl -u nfqws2 -n 200 --no-pager | grep -oE '\-\-name=[^ ]+' | sort -u
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
      sudo ./blockcheck2.sh "$DOMAIN"
    '')
  ];
}
