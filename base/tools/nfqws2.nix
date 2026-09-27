{
  config,
  lib,
  pkgs,
  ...
}: let
  # Директория с ресурсами zapret2 (Lua-скрипты).
  ZAPRET_BASE = "/opt/zapret2";

  # Номер очереди NFQUEUE.
  QNUM = "200";

  # Метка, которой sing-box помечает трафик для nfqws2.
  # Должна совпадать с routing_mark = 110 в signbox.nix.
  DESYNC_MARK = "0x40000000";

  # =====================================================================
  # СТРАТЕГИИ.
  #
  # ВАЖНО: в пакете zapret2 из nixpkgs НЕТ директории blobs/ и .bin-файлов.
  # Поэтому используем только:
  #   - встроенные blob-имена (fake_default_tls — генерируется самим nfqws2);
  #   - чистые Lua-функции (multisplit, disorder, fake, oob, hostfakesplit).
  #
  # Стратегии можно потом подстроить через blockcheck2.sh или вручную.
  # =====================================================================

  # Стратегия для TLS (HTTPS через TCP/443).
  # - multisplit в позиции 1: разбивает ClientHello после первого байта.
  # - fake:blob=fake_default_tls: подставляет фейковый TLS-пакет (встроенный).
  TLS_STRATEGY = [
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1,sniext+1"
    "--lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid"
  ];

  # Стратегия для HTTP (TCP/80).
  HTTP_STRATEGY = [
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2"
  ];

  # Стратегия для QUIC (UDP/443).
  # Используем fake с встроенным blob (без внешнего файла).
  QUIC_STRATEGY = [
    "--filter-udp=443"
    "--filter-l7=quic"
    "--payload=quic_initial"
    "--lua-desync=fake:blob=fake_default_quic:repeats=6"
  ];

  # Общие аргументы.
  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
  ];

  ALL_ARGS = BASE_ARGS ++ TLS_STRATEGY ++ HTTP_STRATEGY ++ QUIC_STRATEGY;
in {
  # =====================================================================
  # nfqws2 (zapret2) — демон обхода DPI через NFQUEUE.
  #
  # ВАЖНО:
  # - nfqws2 — это НЕ SOCKS-прокси, а перехватчик пакетов через NFQUEUE.
  # - sing-box направляет трафик в outbound "zapret-out"
  #   (routing_mark = 110). nftables видит метку и заворачивает
  #   первые пакеты в очередь NFQUEUE, где их обрабатывает nfqws2.
  # - Стратегии используют только встроенные blobs nfqws2,
  #   потому что пакет zapret2 из nixpkgs не содержит .bin-файлов.
  # =====================================================================

  # Симлинки на ресурсы zapret2.
  # Директории blobs/ в пакете НЕТ, поэтому её не линкуем.
  systemd.tmpfiles.rules = [
    "d /opt/zapret2 0755 root root -"
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"
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
  #   3. nfqws2 обрабатывает пакеты и возвращает их в стек.
  #
  # ИСПРАВЛЕНО:
  # - meta mark 110 (точное сравнение) вместо "mark & 0x6e == 0x6e".
  # - Убрано "--user=root" — вызывало конфликт с systemd User=root.
  # =====================================================================
  networking.nftables.ruleset = ''
    table inet zapret_nfqws2 {
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        # Пропускаем пакеты, уже обработанные nfqws2.
        meta mark and ${DESYNC_MARK} != 0 return

        # TCP 80, 443 — первые 6 пакетов.
        meta mark 110 tcp dport {80, 443} \
          ct original packets 1-6 queue num ${QNUM} bypass

        # UDP 443 (QUIC) — первые 6 пакетов.
        meta mark 110 udp dport 443 \
          ct original packets 1-6 queue num ${QNUM} bypass
      }

      chain prerouting {
        type filter hook prerouting priority -101; policy accept;
        meta mark and ${DESYNC_MARK} == ${DESYNC_MARK} return
      }
    }
  '';

  # =====================================================================
  # Скрипты для управления и диагностики.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    # --- nfqws2-status ---
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
      echo "=== nftables ==="
      sudo nft list table inet zapret_nfqws2 2>/dev/null || \
        echo "  таблица zapret_nfqws2 не найдена"
    '')

    # --- nfqws2-find-strategy ---
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
