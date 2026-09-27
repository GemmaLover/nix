{
  config,
  lib,
  pkgs,
  ...
}: let
  # =====================================================================
  # КОНСТАНТЫ
  # =====================================================================

  # Директория с ресурсами zapret2 (Lua-скрипты).
  # Создаётся через systemd.tmpfiles как симлинк на ${pkgs.zapret2}/share/zapret2.
  # nfqws2 ищет Lua-файлы именно по этому пути.
  ZAPRET_BASE = "/opt/zapret2";

  # Номер очереди NFQUEUE.
  # 200 — стандартный для zapret2. nftables заворачивает пакеты
  # в эту очередь через `queue num 200`, а nfqws2 их обрабатывает.
  QNUM = "200";

  # Метка, которой sing-box помечает трафик для nfqws2.
  # Должна совпадать с routing_mark = 110 в signbox.nix (outbound zapret-out).
  # sing-box ставит mark 110 на пакеты → nftables видит метку
  # → queue num 200 → nfqws2 обрабатывает.
  DESYNC_MARK = "0x40000000";

  # =====================================================================
  # СТРАТЕГИИ ОБХОДА DPI
  #
  # ВАЖНО ПРО ОТСУТСТВИЕ FAKE:
  # Раньше использовалась функция `fake`, которая создаёт дополнительный
  # поддельный пакет (fake TLS ClientHello и т.п.). Это вызывало ошибки
  # "rawsend: sendto (1480): Message too long" — fake-пакет не влезал
  # в MTU физического интерфейса (wlp194s0 = 1500), и nfqws2 не мог
  # его отправить.
  #
  # Поэтому используем ТОЛЬКО функции, которые НЕ добавляют данные:
  #   - multisplit: разбивает оригинальный пакет на части в заданных
  #     позициях, не создавая новых пакетов. Итоговый размер = исходный.
  #   - multidisorder: разбивает пакет и отправляет фрагменты
  #     в обратном порядке. Тоже не добавляет данных.
  #
  # Эти двух функций достаточно для обхода большинства DPI:
  #   DPI не может собрать целый TLS ClientHello, если он разбит
  #   на части в правильных позициях (например, внутри SNI).
  #
  # ПОЗИЦИИ В multisplit:
  #   pos=1          — после первого байта (разбивает TLS record header)
  #   pos=sniext+1   — сразу после расширения SNI (разбивает внутри SNI)
  #   pos=method+2   — для HTTP: после метода и пробела ("GET /...")
  #   pos=midsld     — в середине второго уровня домена
  #   pos=endhost    — в конце хоста
  # =====================================================================

  # --- Стратегия для TLS (HTTPS через TCP/443) ---
  # filter-tcp=443     — обрабатываем только порт 443.
  # filter-l7=tls      — только TLS-трафик.
  # payload=tls_client_hello — применяем стратегии к TLS ClientHello.
  #
  # multisplit:pos=1           — разбиваем пакет после первого байта.
  #   Это ломает TLS record header (0x16 0x03 ...), DPI не может
  #   определить протокол.
  # multisplit:pos=sniext+1    — разбиваем сразу после расширения SNI.
  #   DPI не может прочитать имя домена в SNI.
  TLS_STRATEGY = [
    "--filter-tcp=443"
    "--filter-l7=tls"
    "--payload=tls_client_hello"
    "--lua-desync=multisplit:pos=1"
    "--lua-desync=multisplit:pos=sniext+1"
  ];

  # --- Стратегия для HTTP (TCP/80) ---
  # filter-tcp=80      — только порт 80.
  # filter-l7=http     — только HTTP-трафик.
  # payload=http_req   — применяем стратегии к HTTP-запросу.
  #
  # multisplit:pos=method+2 — разбиваем после метода и пробела
  #   (например, "GET " → 4 байта). DPI не может определить URL.
  HTTP_STRATEGY = [
    "--filter-tcp=80"
    "--filter-l7=http"
    "--payload=http_req"
    "--lua-desync=multisplit:pos=method+2"
  ];

  # --- Общие аргументы (применяются ко всем стратегиям) ---
  # --qnum=200                       — номер очереди NFQUEUE.
  # --lua-init=@.../zapret-lib.lua   — базовая библиотека Lua.
  # --lua-init=@.../zapret-antidpi.lua — библиотека с функциями
  #   десинхронизации (multisplit, multidisorder и т.д.).
  BASE_ARGS = [
    "--qnum=${QNUM}"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-lib.lua"
    "--lua-init=@${ZAPRET_BASE}/lua/zapret-antidpi.lua"
  ];

  # Итоговый список аргументов для nfqws2.
  ALL_ARGS = BASE_ARGS ++ TLS_STRATEGY ++ HTTP_STRATEGY;
in {
  # =====================================================================
  # СИМЛИНКИ НА РЕСУРСЫ ZAPRET2
  #
  # nfqws2 ожидает Lua-скрипты по пути /opt/zapret2/lua/...
  # В NixOS они лежат в /nix/store/.../share/zapret2/lua/...
  # Поэтому создаём симлинки.
  #
  # Интерполяция ${pkgs.zapret2} вычисляется НА ЭТАПЕ СБОРКИ,
  # поэтому при обновлении пакета zapret2 симлинки автоматически
  # пересоздаются с актуальным путём. Флаг "L+" пересоздаёт
  # симлинк (удаляет старый, создаёт новый).
  #
  # "d" — создать директорию.
  # "L+" — создать/пересоздать симлинк.
  # =====================================================================
  systemd.tmpfiles.rules = [
    # Корневая директория.
    "d /opt/zapret2 0755 root root -"

    # Lua-скрипты (zapret-lib.lua, zapret-antidpi.lua и т.д.)
    # — нужны nfqws2 для работы стратегий.
    "L+ /opt/zapret2/lua - - - - ${pkgs.zapret2}/share/zapret2/lua"

    # Общие скрипты (base.sh, linux_fw.sh и т.д.)
    # — используются blockcheck2.sh.
    "L+ /opt/zapret2/common - - - - ${pkgs.zapret2}/share/zapret2/common"

    # Директория nfq2 с бинарником nfqws2 и вспомогательными утилитами.
    "d /opt/zapret2/nfq2 0755 root root -"
    "L+ /opt/zapret2/nfq2/nfqws2 - - - - ${pkgs.zapret2}/bin/nfqws2"
  ];

  # =====================================================================
  # SYSTEMD-СЕРВИС NFQWS2
  #
  # nfqws2 — это демон, который:
  #   1. Привязывается к очереди NFQUEUE (num 200).
  #   2. Получает пакеты из ядра (те, что nftables завернул в очередь).
  #   3. Применяет Lua-стратегии (multisplit, multidisorder).
  #   4. Отправляет изменённые пакеты обратно в сеть.
  #
  # ЗАПУСК ОТ ROOT:
  # nfqws2 требует root для:
  #   - работы с NFQUEUE;
  #   - создания raw-сокетов для отправки пакетов;
  #   - изменения пакетов.
  #
  # Флаг --user=root НЕ используем (вызывал конфликт).
  # Вместо этого User=root в serviceConfig.
  # =====================================================================
  systemd.services.nfqws2 = {
    description = "nfqws2 (zapret2) DPI bypass daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "nftables.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.zapret2}/bin/nfqws2 " + lib.concatStringsSep " " ALL_ARGS;

      # Перезапускать при падении.
      Restart = "on-failure";
      RestartSec = 5;

      # nfqws2 требует root для NFQUEUE и raw-сокетов.
      User = "root";
      Group = "root";

      # Безопасность.
      # NoNewPrivileges — запрет на повышение привилегий.
      # ProtectSystem = "full" — /usr, /boot, /etc read-only.
      # ProtectHome = true — /home read-only.
      # ReadWritePaths — куда разрешена запись (нужно для логов).
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ProtectHome = true;
      ReadWritePaths = [ "/run" "/var/log" ];

      # Логирование в journal.
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # =====================================================================
  # NFTABLES: ПЕРЕХВАТ ТРАФИКА С MARK 110
  #
  # Логика:
  #   1. sing-box направляет трафик в outbound "zapret-out"
  #      с routing_mark = 110.
  #   2. Пакеты с mark 110 попадают в цепочку postrouting.
  #   3. nftables заворачивает первые 6 пакетов каждого соединения
  #      в очередь NFQUEUE (num 200).
  #   4. nfqws2 обрабатывает эти пакеты (multisplit и т.д.).
  #   5. Обработанные пакеты получают mark DESYNC_MARK (0x40000000)
  #      и больше не перехватываются (защита от петли).
  #
  # ПОЧЕМУ 6 ПАКЕТОВ:
  # TLS ClientHello обычно влезает в 1-2 пакета. HTTP-запрос — 1-2.
  # 6 — с запасом на фрагментацию. Больше не нужно.
  #
  # ИСКЛЮЧЕНИЯ:
  #   - DNS (порт 53) — не перехватываем (иначе сломается DNS).
  #   - Локальные адреса (127.0.0.0/8, ::1) — не перехватываем.
  # =====================================================================
  networking.nftables.ruleset = ''
    table inet zapret_nfqws2 {
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;

        # Пропускаем пакеты, уже обработанные nfqws2.
        # Если на пакете уже стоит DESYNC_MARK — не перехватываем повторно.
        meta mark and ${DESYNC_MARK} != 0 return

        # Исключения: DNS и loopback.
        meta mark 110 udp dport 53 return
        meta mark 110 tcp dport 53 return
        meta mark 110 ip daddr 127.0.0.0/8 return
        meta mark 110 ip6 daddr ::1 return

        # Перехватываем TCP 80, 443 — первые 6 пакетов каждого соединения.
        meta mark 110 tcp dport {80, 443} \
          ct original packets 1-6 queue num ${QNUM} bypass

        # Перехватываем UDP 443 (QUIC) — первые 6 пакетов.
        # (пока QUIC не обрабатываем, но правило оставим на будущее)
        meta mark 110 udp dport 443 \
          ct original packets 1-6 queue num ${QNUM} bypass
      }

      # Цепочка prerouting: защита от повторного перехвата.
      # Если пакет уже помечен DESYNC_MARK — пропускаем.
      chain prerouting {
        type filter hook prerouting priority -101; policy accept;
        meta mark and ${DESYNC_MARK} == ${DESYNC_MARK} return
      }
    }
  '';

  # =====================================================================
  # УТИЛИТЫ ДЛЯ УПРАВЛЕНИЯ И ДИАГНОСТИКИ
  # =====================================================================
  environment.systemPackages = with pkgs; [
    # --- nfqws2-status: показать текущий статус и правила ---
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

    # --- nfqws2-find-strategy: поиск стратегий через blockcheck2.sh ---
    # Использование: sudo nfqws2-find-strategy youtube.com
    (writeShellScriptBin "nfqws2-find-strategy" ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Использование: nfqws2-find-strategy <domain>"
        echo "Пример: nfqws2-find-strategy youtube.com"
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
