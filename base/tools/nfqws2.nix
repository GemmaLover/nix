{
  config,
  lib,
  pkgs,
  ...
}: let
  # Директория с ресурсами zapret2 (Lua-скрипты, blobs).
  ZAPRET_BASE = "/opt/zapret2";

  # Номер очереди NFQUEUE. 200 — стандартный для zapret2.
  QNUM = "200";

  # Метка, которой sing-box помечает трафик для nfqws2.
  # Должна совпадать с routing_mark = 110 в signbox.nix.
  DESYNC_MARK = "0x40000000";

  # Базовая стратегия для TCP/HTTPS (адаптирована из конфига GoldDopi).
  # Использует Lua-десинхронизацию из zapret2.
  TCP_STRATEGY = [
    "--filter-tcp=443,80"
    "--filter-l7=http,tls"
    "--payload=tls_client_hello"
    "--lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1000"
    "--lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up"
    "--payload=http_req"
    "--lua-desync=http_methodeol:badsum"
  ];

  # Стратегия для QUIC.
  QUIC_STRATEGY = [
    "--filter-udp=443"
    "--filter-l7=quic"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=quic_initial:repeats=6"
  ];

  # Стратегия для Discord и другого UDP-трафика.
  UDP_STRATEGY = [
    "--filter-udp=590-600,1400,3478-3481,5349,19294-19344,50000-65535"
    "--filter-l7=wireguard,stun,discord,mtproto"
    "--out-range=-n1"
    "--payload=wireguard_initiation,wireguard_response,wireguard_cookie,stun,discord_ip_discovery,mtproto_initial"
    "--lua-desync=fake:blob=quic_initial:repeats=6"
  ];

  # Общие аргументы (Lua-init, blobs).
  BASE_ARGS = [
    "--user=root"
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
    "--blob=quic_initial:@${pkgs.zapret2}/share/zapret2/blobs/quic_initial.bin"
    "--blob=tls_clienthello:@${pkgs.zapret2}/share/zapret2/blobs/tls_clienthello.bin"
  ];

  ALL_ARGS = BASE_ARGS ++ TCP_STRATEGY ++ QUIC_STRATEGY ++ UDP_STRATEGY;
in {
  # =====================================================================
  # nfqws2 (zapret2) — демон обхода DPI через NFQUEUE.
  #
  # ВАЖНО:
  # - nfqws2 — это НЕ SOCKS-прокси, а перехватчик пакетов через NFQUEUE.
  # - sing-box направляет трафик в специальный outbound "zapret-out"
  #   (routing_mark = 110). nftables видит метку и заворачивает
  #   первые пакеты в очередь NFQUEUE, где их обрабатывает nfqws2.
  # - Lua-стратегии берутся из пакета pkgs.zapret2.
  # - Симлинки /opt/zapret2/* → ${pkgs.zapret2}/share/zapret2/*
  #   создаются через systemd.tmpfiles, чтобы nfqws2 нашёл свои ресурсы.
  # =====================================================================

  # Симлинки на ресурсы zapret2.
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/files - - - - ${pkgs.zapret2}/share/zapret2/files"
    "L+ /opt/zapret2/blobs - - - - ${pkgs.zapret2}/share/zapret2/blobs"
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  # systemd-сервис для nfqws2.
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

      # nfqws2 требует root для работы с NFQUEUE и изменения пакетов.
      User = "root";
      Group = "root";

      # Безопасность
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/run" "/var/log" ];

      StandardOutput = "journal";
      StandardError = "journal";
      RestartIfChanged = true;
    };
  };

  # =====================================================================
  # Правила nftables для перенаправления трафика в NFQUEUE.
  #
  # Логика:
  #   1. sing-box помечает трафик для nfqws2 меткой 110 (routing_mark).
  #   2. nftables в цепочке postrouting видит метку и заворачивает
  #      первые 6 пакетов каждого соединения в NFQUEUE.
  #   3. nfqws2 обрабатывает пакеты и возвращает их в стек
  #      с меткой DESYNC_MARK (0x40000000), чтобы избежать повторного
  #      перехвата.
  # =====================================================================
  networking.nftables.ruleset = ''
    table inet zapret_nfqws2 {
      # Цепочка postrouting: перехватывает исходящий трафик
      # с меткой 110 (routing_mark из sing-box).
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        # Пропускаем пакеты, уже обработанные nfqws2 (метка DESYNC_MARK).
        meta mark and ${DESYNC_MARK} != 0 return

        # Перехватываем TCP:80,443 — первые 6 пакетов соединения.
        meta mark and 0x0000006e == 110 tcp dport {80, 443} \
          ct original packets 1-6 queue num ${QNUM} bypass

        # Перехватываем UDP:443 (QUIC) — первые 6 пакетов.
        meta mark and 0x0000006e == 110 udp dport 443 \
          ct original packets 1-6 queue num ${QNUM} bypass

        # Перехватываем UDP-порты для Discord, STUN, WireGuard.
        meta mark and 0x0000006e == 110 udp dport {590-600, 1400, 3478-3481, 5349, 19294-19344, 50000-65535} \
          ct original packets 1-6 queue num ${QNUM} bypass
      }

      # Цепочка prerouting: пропускаем уже обработанные пакеты.
      chain prerouting {
        type filter hook prerouting priority -101; policy accept;
        meta mark and ${DESYNC_MARK} == ${DESYNC_MARK} return
      }
    }
  '';

  # =====================================================================
  # Скрипты для поиска стратегий и просмотра статуса.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    # --- nfqws2-status: показать статус nfqws2 и правила nftables ---
    (writeShellScriptBin "nfqws2-status" ''
      #!/usr/bin/env bash
      echo "=== nfqws2 (zapret2) ==="
      if systemctl is-active --quiet nfqws2 2>/dev/null; then
        echo "Статус: активен"
      else
        echo "Статус: неактивен"
      fi
      echo ""
      echo "=== Очередь NFQUEUE ==="
      sudo ss -tlnp | grep ${QNUM} || echo "  очередь не слушается"
      echo ""
      echo "=== Правила nftables ==="
      sudo nft list table inet zapret_nfqws2 2>/dev/null || \
        echo "  таблица zapret_nfqws2 не найдена"
      echo ""
      echo "=== ExecStart ==="
      systemctl cat nfqws2 2>/dev/null | grep -A3 "ExecStart" || \
        echo "  unit не найден"
    '')

    # --- nfqws2-find-strategy: поиск стратегий через blockcheck2.sh ---
    (writeShellScriptBin "nfqws2-find-strategy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Использование: nfqws2-find-strategy <domain>"
        echo "Пример: nfqws2-find-strategy instagram.com"
        exit 1
      fi

      DOMAIN="$1"

      BLOCKCHECK=$(find ${zapret2}/ -name "blockcheck2.sh" -type f 2>/dev/null | head -1)
      if [ -z "$BLOCKCHECK" ]; then
        echo "Ошибка: blockcheck2.sh не найден в пакете zapret2." >&2
        exit 1
      fi

      BLOCKCHECK_DIR=$(dirname "$BLOCKCHECK")

      echo "==> Запуск blockcheck2.sh для домена: $DOMAIN"
      echo "==> Директория: $BLOCKCHECK_DIR"
      echo ""

      cd "$BLOCKCHECK_DIR"
      sudo ./blockcheck2.sh "$DOMAIN"
    '')

    # --- blockcheckw (уже установлен) ---
    # blockcheckw --version
    # sudo blockcheckw scan -d instagram.com
  ];
}
