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
  # Все 9 тестовых доменов (instagram, youtube, rutracker, telegram,
  # virustotal, discord, x.com, twitter, facebook) — SNI blocked.
  # Значит DPI читает SNI из TLS ClientHello и блокирует соединение.
  #
  # БАЗОВАЯ СТРАТЕГИЯ (multisplit:pos=1) работала только для YouTube,
  # потому что:
  #   - она ломала TLS record header (0x16 0x03 ...),
  #   - но SNI внутри ClientHello оставался целым,
  #   - простой DPI YouTube не смотрел глубже заголовка,
  #   - сложные DPI (Instagram, Discord) читают SNI и блокируют.
  #
  # НОВАЯ СТРАТЕГИЯ — multisplit с НЕСКОЛЬКИМИ позициями:
  #   pos=1         — после TLS record header (0x16 0x03 0x01 ...)
  #   pos=sniext+1  — сразу после начала расширения SNI
  #   pos=sniext+4  — внутри SNI, ломает имя домена
  #   pos=host+1    — внутри имени хоста (если sni не сработал)
  #
  # Одна опция multisplit создаёт 4-5 фрагментов из ОДНОГО пакета.
  # Суммарный размер не превышает исходный — поэтому "Message too long"
  # не возвращается (в отличие от fake, который ДОБАВЛЯЕТ данные).
  #
  # Если и это не поможет — можно добавить multidisorder
  # (отправка фрагментов в обратном порядке). Он тоже не создаёт
  # новых пакетов.
  # =====================================================================

  # --- Стратегия для TLS (HTTPS через TCP/443) ---
  TLS_STRATEGY = [
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1,sniext+1,sniext+4"
    "--lua-desync=multidisorder:pos=1,sniext+1"
  ];

  # --- Стратегия для HTTP (TCP/80) ---
  HTTP_STRATEGY = [
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2,host+2"
  ];

  # --- Общие аргументы ---
  # --filter-l3=ipv4 — обрабатываем только IPv4.
  #   IPv6-пакеты не должны попадать в nfqws2, иначе
  #   "Message too long" (1480 + 40 = 1520 > 1500).
  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--filter-l3=ipv4"
  ];

  ALL_ARGS = BASE_ARGS ++ TLS_STRATEGY ++ HTTP_STRATEGY;
in {
  # =====================================================================
  # СИМЛИНКИ НА РЕСУРСЫ ZAPRET2
  # =====================================================================
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  # =====================================================================
  # SYSTEMD-СЕРВИС NFQWS2
  #
  # Зависит от sing-box (TUN должен быть готов до старта nfqws2).
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
      sudo ./blockcheck2.sh "$DOMAIN"
    '')
  ];
}
