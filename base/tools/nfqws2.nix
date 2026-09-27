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
  # РАЗДЕЛЬНЫЕ СТРАТЕГИИ ПО КАТЕГОРИЯМ САЙТОВ
  #
  # ВАЖНО: X.com, Instagram, Discord используют QUIC (UDP/443).
  # Если профиль не обрабатывает UDP — пакеты уходят без обхода,
  # и DPI их блокирует. Поэтому для каждого сайта ДВА профиля:
  #   - TCP (TLS через 443)
  #   - UDP (QUIC через 443)
  #
  # Все профили используют --new для разделения.
  # Порядок: сначала все TCP, потом все UDP.
  # =====================================================================

  BLOBS = [
    "--blob=quic_initial:@${ZAPRET_BASE}/blobs/quic_initial.bin"
    "--blob=tls_clienthello:@${ZAPRET_BASE}/blobs/tls_clienthello.bin"
    "--blob=tls_google:@${ZAPRET_BASE}/blobs/tls_clienthello_www_google_com.bin"
    "--blob=quic_google:@${ZAPRET_BASE}/blobs/quic_initial_www_google_com.bin"
    "--blob=tls_max:@${ZAPRET_BASE}/blobs/tls_clienthello_max_ru.bin"
    "--blob=stun:@${ZAPRET_BASE}/blobs/stun.bin"
    "--blob=quic_dbankcloud:@${ZAPRET_BASE}/blobs/quic_initial_dbankcloud_ru.bin"
    "--blob=blob_zero:0x00000000"
  ];

  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--filter-l3=ipv4"
  ] ++ BLOBS;

  STRATEGY = [
    # =================================================================
    # ПРОФИЛЬ 1: YouTube (TCP) — лёгкая, проверено
    # =================================================================
    "--name=YouTube-TCP"
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-youtube.list"
    "--lua-desync=multisplit:pos=1,sniext+1"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 2: YouTube (QUIC) — fake
    # =================================================================
    "--name=YouTube-QUIC"
    "--filter-udp=443"
    "--filter-l7=quic"
    "--hostlist=${ZAPRET_BASE}/lists/domain-youtube.list"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=quic_initial:repeats=6"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 3: X.com / Twitter (TCP)
    # =================================================================
    # hostfakesplit подменяет SNI на ya.ru и разбивает пакет.
    # Стратегия мягкая, не создаёт fake-пакетов → нет "Message too long".
    "--name=X-TCP"
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-x.list"
    "--lua-desync=hostfakesplit:host=ya.ru:repeats=4:tcp_ts=-600000"
    "--lua-desync=multisplit:pos=1,sniext+1"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 4: X.com / Twitter (QUIC) — критично для браузеров!
    # =================================================================
    # X.com использует QUIC. Без этого профиля X.com не работает.
    "--name=X-QUIC"
    "--filter-udp=443"
    "--filter-l7=quic"
    "--hostlist=${ZAPRET_BASE}/lists/domain-x.list"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=quic_google:repeats=6"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 5: Instagram / Facebook (TCP)
    # =================================================================
    "--name=Instagram-TCP"
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-instagram.list"
    "--lua-desync=multisplit:pos=1,sniext+1,host+1"
    "--lua-desync=hostfakesplit:host=ya.ru:repeats=2:tcp_ts=-600000"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 6: Instagram / Facebook (QUIC)
    # =================================================================
    "--name=Instagram-QUIC"
    "--filter-udp=443"
    "--filter-l7=quic"
    "--hostlist=${ZAPRET_BASE}/lists/domain-instagram.list"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=quic_google:repeats=6"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 7: Discord (TCP Media)
    # =================================================================
    "--name=Discord-TCP"
    "--filter-tcp=2053,2083,2087,2096,8443,443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-discord.list"
    "--lua-desync=hostfakesplit:repeats=4:tcp_ts=-600000:host=www.google.com"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 8: Discord (UDP Voice/Media)
    # =================================================================
    "--name=Discord-UDP"
    "--filter-udp=3478-3481,19294-19344,50000-50100"
    "--filter-l7=discord,stun"
    "--payload=discord_ip_discovery,stun"
    "--lua-desync=fake:blob=quic_google:repeats=6"
    "--new"

    # =================================================================
    # ПРОФИЛЬ 9: Fallback "Sites" — для всего остального TCP
    # =================================================================
    # Исключения: банки, госуслуги, локальные сети.
    # YouTube/X/Instagram/Discord сюда НЕ попадают — у них свои профили.
    "--name=Sites"
    "--filter-tcp=80,443,8443"
    "--filter-l7=http,tls"
    "--hostlist-exclude=${ZAPRET_BASE}/lists/domains_exclude.list"
    "--ipset-exclude=${ZAPRET_BASE}/lists/ipset_exclude.list"
    "--payload=http_req,tls_client_hello"
    "--lua-desync=hostfakesplit:repeats=4:tcp_ts=-600000:tcp_md5:host=ya.ru"
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
  # NFTABLES: перехват TCP 80/443 + UDP 443
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
      echo "=== Загруженные профили ==="
      sudo journalctl -u nfqws2 -n 300 --no-pager | grep -oE 'name=[^ ]+' | sort -u
      echo ""
      echo "=== Списки ==="
      ls /opt/zapret2/lists/
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
