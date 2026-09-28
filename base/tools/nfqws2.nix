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
  # СТРАТЕГИИ
  #
  # УРОК ПРО X-TCP С seqovl:
  # Профиль X-TCP с `seqovl_pattern=tls_max:seqovl=664` ломал TCP-стек —
  # curl зависал на ~4 КБ, в логах nfqws2 записей не было. Пакеты с
  # перекрывающимися sequence-номерами сбивают TCP-сессию.
  #
  # Оставляем только проверенные профили:
  #   - YouTube-TCP: multisplit (работает)
  #   - Sites: hostfakesplit для всех остальных (безопасно, не создаёт
  #     fake-пакетов, только подменяет SNI на ya.ru и разбивает)
  # =====================================================================

  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--filter-l3=ipv4"
  ];

  STRATEGY = [
    # === YouTube TCP (проверено) ===
    "--name=YouTube-TCP"
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-youtube.list"
    "--lua-desync=multisplit:pos=1,sniext+1"
    "--new"

    # === Sites: универсальный fallback (включая X.com) ===
    "--name=Sites"
    "--filter-tcp=80,443,8443"
    "--filter-l7=http,tls"
    "--hostlist-exclude=${ZAPRET_BASE}/lists/domains_exclude.list"
    "--ipset-exclude=${ZAPRET_BASE}/lists/ipset_exclude.list"
    "--payload=http_req,tls_client_hello"
    "--lua-desync=hostfakesplit:repeats=2:tcp_ts=-600000:tcp_md5:host=ya.ru"
  ];

  ALL_ARGS = BASE_ARGS ++ STRATEGY;
in {
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
    "L+ /opt/zapret2/blobs - - - - ${./nfqws2/files/blobs}"
    "L+ /opt/zapret2/lists - - - - ${./nfqws2/files/lists}"
  ];

  systemd.services.nfqws2 = {
    description = "nfqws2 (zapret2) DPI bypass daemon";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "nftables.service"
      "systemd-tmpfiles-resetup.service"
      "sing-box.service"
    ];
    wants = [
      "network-online.target"
      "sing-box.service"
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.zapret2}/bin/nfqws2 " + lib.concatStringsSep " " ALL_ARGS;
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = 30;
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
      echo "=== nfqws2 ==="
      systemctl is-active --quiet nfqws2 2>/dev/null && echo "Статус: активен" || echo "Статус: неактивен"
      echo ""
      echo "=== Профили ==="
      systemctl cat nfqws2 | grep -oE 'name=[^ ]+' | sort -u
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
