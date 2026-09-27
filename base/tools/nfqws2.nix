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

  # Директория с файлами blobs/lists (внутри репозитория).
  # Nix подставляет абсолютный путь к директории, где лежит этот .nix файл.
  # То есть ${./.} = /nix/store/...-source/base/tools/nfqws2
  FILES_DIR = ./.;

  QNUM = "200";
  DESYNC_MARK = "0x40000000";

  # =====================================================================
  # СТРАТЕГИЯ GOLDDOPI (Dom.ru)
  #
  # Источник:
  # https://github.com/nfqws/nfqws2-keenetic/discussions/2
  # #discussioncomment-17512647
  #
  # Все blobs и lists лежат в base/tools/nfqws2/files/.
  # Симлинки создаются в /opt/zapret2/blobs и /opt/zapret2/lists.
  # =====================================================================

  # --- Blobs ---
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

  # --- Lua + базовые аргументы ---
  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--filter-l3=ipv4"
  ] ++ BLOBS;

  # --- Стратегия (полная от GoldDopi) ---
  STRATEGY = [
    # === Профиль 1: YouTube QUIC ===
    "--filter-udp=443"
    "--filter-l7=quic"
    "--hostlist=${ZAPRET_BASE}/lists/domain-youtube.list"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=quic_initial:repeats=11"
    "--new"

    # === Профиль 2: YouTube TLS ===
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--hostlist=${ZAPRET_BASE}/lists/domain-youtube.list"
    "--lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1"
    "--lua-desync=fake:blob=tls_clienthello:optional:tcp_seq=-10000:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=rzd.ru:repeats=4"
    "--new"

    # === Профиль 3: IPset OVH ===
    "--ipset=${ZAPRET_BASE}/lists/ipset_ovh.list"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=hostfakesplit:host=ya.ru:tcp_md5:badsum"
    "--new"

    # === Профиль 4: Discord UDP ===
    "--name=Discord-UDP"
    "--filter-udp=3478-3481,19294-19344,50000-50100"
    "--filter-l7=discord,stun"
    "--payload=discord_ip_discovery,stun"
    "--lua-desync=fake:blob=quic_google:repeats=6"
    "--new"

    # === Профиль 5: Discord Media ===
    "--name=Discord-Media"
    "--filter-tcp=2053,2083,2087,2096,8443"
    "--hostlist-domains=discord.media"
    "--lua-desync=hostfakesplit:repeats=4:tcp_ts=-600000:host=www.google.com"
    "--new"

    # === Профиль 6: Sites (главный для x.com, instagram) ===
    "--name=Sites"
    "--filter-tcp=80,443,8443"
    "--filter-l7=http,tls"
    "--hostlist-exclude=${ZAPRET_BASE}/lists/domains_exclude.list"
    "--ipset-exclude=${ZAPRET_BASE}/lists/ipset_exclude.list"
    "--payload=http_req,tls_client_hello"
    "--lua-desync=hostfakesplit:repeats=4:tcp_ts=-600000:tcp_md5:host=ya.ru"
    "--new"

    # === Профиль 7: Games TCP ===
    "--name=GamesTCP"
    "--filter-tcp=1024-65535"
    "--ipset-exclude=${ZAPRET_BASE}/lists/ipset_exclude.list"
    "--payload=tls_client_hello"
    "--lua-desync=fake:blob=stun:repeats=8:tcp_ts=-600000"
    "--lua-desync=multisplit:seqovl_pattern=tls_max:seqovl=664:pos=1"
    "--new"

    # === Профиль 8: Games UDP ===
    "--name=GamesUDP"
    "--filter-udp=1024-65535"
    "--ipset-exclude=${ZAPRET_BASE}/lists/ipset_exclude.list"
    "--lua-desync=fake:blob=quic_dbankcloud:repeats=10"
  ];

  ALL_ARGS = BASE_ARGS ++ STRATEGY;
in {
  # =====================================================================
  # СИМЛИНКИ НА РЕСУРСЫ
  # =====================================================================
  systemd.tmpfiles.rules = [
    # Базовые ресурсы zapret2 из nixpkgs
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"

    # Blobs и lists из репозитория (${FILES_DIR}/blobs и ${FILES_DIR}/lists)
    "L+ /opt/zapret2/blobs - - - - ${FILES_DIR}/blobs"
    "L+ /opt/zapret2/lists - - - - ${FILES_DIR}/lists"
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
  # NFTABLES: перехват трафика с mark 110, только IPv4.
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
      sudo journalctl -u nfqws2 -n 200 --no-pager | grep -oE '\-\-name=[^ ]+' | sort -u
      echo ""
      echo "=== Файлы ==="
      ls /opt/zapret2/blobs/ 2>/dev/null | head -5
      echo "..."
      ls /opt/zapret2/lists/ 2>/dev/null | head -5
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
