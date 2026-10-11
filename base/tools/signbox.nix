{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # sing-box — маршрутизация TCP/UDP-трафика по процессам.
  #
  # Модель трафика:
  # ┌─────────────────────────────────────────────────────────────┐
  # │ dnscrypt-proxy (127.0.0.1:53 и :5353)                       │
  # │ - шифрует DNS (DoH) → Cloudflare/Quad9/Scaleway             │
  # │ - HTTP/3 отключён, TCP-ONLY                                  │
  # ├─────────────────────────────────────────────────────────────┤
  # │ nfqws2 (zapret2) — перехват пакетов через NFQUEUE.          │
  # │ Трафик направляется в outbound "zapret-out" с              │
  # │ routing_mark = 110. nftables видит метку и заворачивает    │
  # │ пакеты в очередь 200, где nfqws2 применяет Lua-стратегии.  │
  # ├─────────────────────────────────────────────────────────────┤
  # │ sing-box (TUN singtun0)                                      │
  # │ - DNS НЕ трогает (dns_mode = "disabled")                    │
  # │ - dnscrypt-proxy → dns-out (гарантированный обход TUN)       │
  # │ - Chromium/Firefox/всё остальное → SELECTOR "system-out"     │
  # │   Переключается между:                                       │
  # │     * zapret-out   — обычный режим (обход DPI через nfqws2)  │
  # │     * waydroid-out — SOCKS5 на 192.168.240.112:1080          │
  # │                      (VPN внутри Waydroid, включается вручную)│
  # │   Переключение — команды waydroid-vpn-connect / -disconnect. │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - routing_mark = 110 в OUTBOUND — правильный способ помечать
  #   пакеты для nfqws2. В TUN inbound такой опции НЕТ.
  # - default_mark = 8227 — помечает все исходящие сокеты sing-box
  #   (для разрыва петли через TUN). Отдельная метка,
  #   НЕ связана с routing_mark = 110.
  # - stack = "gvisor" — КРИТИЧНО.
  # - IPv6-адрес на TUN УБРАН (ядро Linux отклоняет его при MTU 1280
  #   с ошибкой "invalid argument"). У нас нет рабочего IPv6
  #   от провайдера, DNS не отдаёт AAAA-записи (block_ipv6 = true).
  # - MTU = 1300 — компромисс между:
  #     * минимумом для gvisor (~1280);
  #     * необходимостью, чтобы nfqws2 не получал пакеты 1480+,
  #       которые не влезают в raw socket.
  #
  # === SELECTOR system-out ===
  # Все правила маршрутизации (кроме DNS, NTP, loopback) направлены
  # в selector "system-out". Переключение через Clash API
  # (127.0.0.1:9090) — без перезапуска sing-box, текущие сессии
  # не рвутся.
  #
  # Выбор selector сохраняется в /var/lib/sing-box/cache.db —
  # это StateDirectory сервиса (systemd создаёт его сам и выставляет
  # ownership под DynamicUser). Путь /var/cache/sing-box использовать
  # НЕЛЬЗЯ: он не создаётся автоматически и даёт permission denied
  # под DynamicUser.
  #
  # Управление (в environment.systemPackages ниже):
  #   waydroid-vpn-connect     — переключить на waydroid-out (VPN)
  #   waydroid-vpn-disconnect  — вернуть на zapret-out (обычный)
  #   waydroid-vpn-status      — показать текущий режим
  # =====================================================================
  services.sing-box = {
    enable = true;
    settings = {
      log = {
        level = "info";
      };

      # =============================================================
      # Clash API + cache
      # =============================================================
      # Clash API — для управления selector'ом на лету (PUT /proxies).
      # Слушает только на 127.0.0.1, доступен локально без аутентификации.
      #
      # cache_file — сохраняет выбор selector между перезапусками
      # sing-box (например, при nixos-rebuild или reboot).
      #
      # Путь /var/lib/sing-box — это StateDirectory модуля sing-box в
      # nixpkgs. systemd создаёт каталог сам и выставляет ownership
      # под DynamicUser сервиса, поэтому запись разрешена без root.
      # /var/cache/sing-box использовать нельзя — этот путь не
      # создаётся автоматически (systemd.tmpfiles с root ownership
      # не помогает — DynamicUser всё равно получит permission denied).
      experimental = {
        clash_api.external_controller = "127.0.0.1:9090";
        cache_file = {
          enabled = true;
          path = "/var/lib/sing-box/cache.db";
        };
      };

      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";

          # address: только IPv4-префикс.
          # IPv6-адрес убран, потому что ядро отклоняет его на TUN
          # при MTU <= 1280 с ошибкой "invalid argument".
          address = [
            "172.19.0.1/30"
          ];

          # dns_mode = "disabled": sing-box НЕ перехватывает DNS.
          dns_mode = "disabled";

          auto_route = true;
          strict_route = false;

          # MTU TUN-интерфейса.
          # 1300 — компромисс:
          #   * > 1280 (минимум для gvisor);
          #   * < 1400, чтобы пакеты, которые nfqws2 отправляет
          #     через raw socket, не превышали MTU физического
          #     интерфейса (1500) с учётом накладных расходов.
          mtu = 1300;

          stack = "gvisor";
        }
      ];

      outbounds = [
        # socks-out — заготовка на будущее (реального SOCKS-сервера
        # на 127.0.0.1 сейчас нет; есть waydroid-out ниже). ВНИМАНИЕ:
        # правила маршрутизации на него НЕ направлены.
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";
          server_port = 1080;
          version = "5";
          username = "chelik";
          password = "pass11";
        }

        # zapret-out — базовый режим: nfqws2 (обход DPI).
        {
          type = "direct";
          tag = "zapret-out";
          routing_mark = 110;
        }

        # waydroid-out — SOCKS5 внутри Waydroid-контейнера.
        # sing-box for Android (SFA) поднимает прокси на 0.0.0.0:1080,
        # а весь его исходящий трафик идёт через VPN-туннель внутри
        # Android. С хоста доступен по адресу 192.168.240.112 (bridge
        # waydroid0), при условии что применено правило
        # waydroid-fix-route (иначе ответные пакеты уходят в tun0).
        #
        # ВАЖНО: waydroid-out работает только когда:
        #   1. Waydroid запущен,
        #   2. VPN включён ВНУТРИ Android,
        #   3. Применено: waydroid-fix-route
        # При подключении waydroid-vpn-connect всё это проверяется.
        {
          type = "socks";
          tag = "waydroid-out";
          server = "192.168.240.112";
          server_port = 1080;
          version = "5";
        }

        # vless-out — ЗАГЛУШКА на будущее: реального сервера пока нет,
        # через него ничего не отправляем. Параметры хранятся в файле
        # ./sing-box/vless.nix (закоммичен как заглушка с enable = false;
        # flake из git-дерева копирует только отслеживаемые файлы, поэтому
        # файл ОБЯЗАН быть в git — иначе «Path does not exist»).
        # Пока vless.enable = false — тег vless-out это обычный direct.
        (let
          v = import ./sing-box/vless.nix;
        in
          if v.enable or false then {
            type = "vless";
            tag = "vless-out";
            server = v.server;
            server_port = v.port or 443;
            uuid = v.uuid;
            flow = "xtls-rprx-vision";
            tls = {
              enabled = true;
              server_name = v.sni;
              utls = {
                enabled = true;
                fingerprint = "chrome";
              };
            };
          } else {
            type = "direct";
            tag = "vless-out";
          })

        {
          type = "direct";
          tag = "direct-out";
        }
        {
          type = "direct";
          tag = "dns-out";
        }

        # =============================================================
        # SELECTOR system-out — главный переключатель
        # =============================================================
        # Один outbound, который переключается между двумя:
        #   zapret-out   — обычный режим (обход DPI через nfqws2)
        #   waydroid-out — VPN внутри Waydroid (SOCKS5)
        #
        # Переключение — через Clash API:
        #   PUT /proxies/system-out  {"name": "waydroid-out"}
        #   PUT /proxies/system-out  {"name": "zapret-out"}
        # (см. команды waydroid-vpn-connect / -disconnect)
        #
        # default = "zapret-out" — стартовое значение, если cache
        # пуст. После первого переключения cache_file запоминает
        # выбор и восстанавливает его при рестарте.
        {
          type = "selector";
          tag = "system-out";
          outbounds = [ "zapret-out" "waydroid-out" ];
          default = "zapret-out";
        }
      ];

      route = {
        find_process = true;
        auto_detect_interface = true;
        default_mark = 8227;

        rules = [
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }
          {
            # DNS-трафик dnscrypt-proxy: отдельный явный аутбаунд.
            # auto_route добавляет правило main-table для sing-box,
            # но ip rule fwmark 8227 (см. sing-box-fwmark-rule) имеет
            # приоритет 100 и уводит пакеты в main table — на случай
            # гонки маршрутизации держим DNS на гарантированном пути.
            #
            # ВАЖНО: DNS идёт через dns-out (direct), НЕ через selector.
            # Это значит, что при включённом VPN DNS всё равно резолвится
            # напрямую — чтобы резолвинг работал, даже если VPN-туннель
            # внутри Waydroid отвалится.
            process_name = ["dnscrypt-proxy"];
            outbound = "dns-out";
          }
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }

          # =========================================================
          # Правила для приложений → SELECTOR system-out
          # =========================================================
          # Ранее Firefox ходил через direct-out специально, чтобы
          # обойти race condition при старте. Сейчас это не нужно:
          # selector даёт детерминированный выбор режима.
          #
          # Chromium и Firefox направлены в selector, чтобы
          # waydroid-vpn-connect переключал и их тоже.
          {
            process_name = ["chromium"];
            outbound = "system-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "system-out";
          }
          {
            process_name = ["firefox" "firefox-bin"];
            outbound = "system-out";
          }
          {
            process_path_regex = [".*/firefox/firefox.*" ".*/libexec/mozilla-firefox.*"];
            outbound = "system-out";
          }

          # Catch-all: всё остальное — тоже в selector.
          # По умолчанию selector = zapret-out (nfqws2, обход DPI);
          # после waydroid-vpn-connect — waydroid-out (VPN).
          {
            outbound = "system-out";
          }
        ];
      };
    };
  };

  # =====================================================================
  # Systemd-настройки сервиса sing-box.
  #
  # `path` — это ОПЦИЯ NixOS ВЕРХНЕГО УРОВНЯ сервиса (не ключ systemd).
  # Раньше лежала внутри serviceConfig — systemd писал в лог
  # "Unknown key 'path' in section [Service], ignoring" и PATH не
  # подставлялся. Из-за этого sing-box не мог найти iptables/nftables/ip
  # при auto_route. Сейчас path стоит рядом с serviceConfig, NixOS
  # сам разворачивает его в Environment="PATH=...".
  # =====================================================================
  systemd.services.sing-box = {
    serviceConfig = {
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
        "CAP_SYS_PTRACE"
      ];
      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
        "CAP_SYS_PTRACE"
      ];
    };
    # PATH для утилит, которые sing-box вызывает сам
    # (ip route/rule, nftables для auto_route).
    path = [ pkgs.nftables pkgs.iptables pkgs.iproute2 ];
  };

  # =====================================================================
  # Отдельный systemd-сервис: ip rule для fwmark sing-box.
  #
  # default_mark = 8227 помечает все исходящие сокеты самого sing-box,
  # чтобы они не заворачивались обратно в TUN (иначе — петля).
  # Правило fwmark 8227 → main table с приоритетом 100.
  # =====================================================================
  systemd.services.sing-box-fwmark-rule = {
    description = "Add ip rule for sing-box default_mark (break TUN loop, v4+v6)";
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStop = pkgs.writeShellScript "sing-box-fwmark-stop" ''
        ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      '';
    };

    script = ''
      ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true

      ${pkgs.iproute2}/bin/ip    rule add fwmark 8227 lookup main priority 100
      ${pkgs.iproute2}/bin/ip -6 rule add fwmark 8227 lookup main priority 100
    '';
  };

  # =====================================================================
  # Команды управления режимом
  # =====================================================================
  # waydroid-vpn-connect     — переключить всю систему на VPN (Waydroid)
  # waydroid-vpn-disconnect  — вернуть zapret (обход DPI)
  # waydroid-vpn-status      — показать текущий режим
  #
  # Все команды работают через Clash API sing-box (127.0.0.1:9090),
  # переключение мгновенное, без перезапуска сервиса.
  #
  # ВАЖНО про pkgs.netcat-openbsd: в nixpkgs нет пакета pkgs.netcat —
  # команда nc приходит из netcat-openbsd (или netcat-gnu, nmap).
  # Используем netcat-openbsd — он даёт флаг -z для проверки открытия
  # TCP-порта и -w для таймаута.
  # =====================================================================
  environment.systemPackages = [
    # Переключить всю систему на VPN внутри Waydroid.
    (pkgs.writeShellApplication {
      name = "waydroid-vpn-connect";
      runtimeInputs = [ pkgs.curl pkgs.jq pkgs.netcat-openbsd pkgs.coreutils ];
      text = ''
        set -euo pipefail
        API="http://127.0.0.1:9090"

        # --- Проверка 1: Clash API sing-box доступен ---
        if ! curl -fsS "$API/proxies/system-out" >/dev/null 2>&1; then
          echo "ОШИБКА: Clash API sing-box недоступен на $API." >&2
          echo "Проверьте: systemctl status sing-box" >&2
          exit 1
        fi

        # --- Проверка 2: SOCKS5 в Waydroid отвечает ---
        # Проверяем просто открытие TCP-порта, без аутентификации.
        # -z: zero-I/O mode (только проверить соединение)
        # -w 3: таймаут 3 секунды
        if ! nc -z -w 3 192.168.240.112 1080 2>/dev/null; then
          echo "ОШИБКА: SOCKS5 192.168.240.112:1080 не отвечает." >&2
          echo "Убедитесь, что:" >&2
          echo "  1. Waydroid запущен." >&2
          echo "  2. VPN включён ВНУТРИ Android (SFA → Start)." >&2
          echo "  3. Применено правило: waydroid-fix-route" >&2
          exit 1
        fi

        # --- Проверка 3: SOCKS5 реально работает (не только порт открыт) ---
        # Короткий запрос через прокси к внешнему сайту.
        # --socks5-hostname: DNS тоже резолвится через прокси (без утечки).
        if ! curl -fsS --max-time 5 --socks5-hostname 192.168.240.112:1080 \
             https://ifconfig.me >/dev/null 2>&1; then
          echo "ПРЕДУПРЕЖДЕНИЕ: SOCKS5 открыт, но не пропускает трафик." >&2
          echo "VPN внутри Waydroid может быть не готов. Продолжаю переключение..." >&2
        fi

        # --- Переключение selector ---
        curl -fsS -X PUT "$API/proxies/system-out" \
          -H "Content-Type: application/json" \
          -d '{"name":"waydroid-out"}' >/dev/null

        echo "Система переключена на VPN (waydroid-out)."
        echo
        echo "Проверка: curl -s https://ifconfig.me"
        echo "Откат:    waydroid-vpn-disconnect"
      '';
    })

    # Вернуть систему на zapret (обычный режим обхода DPI).
    (pkgs.writeShellApplication {
      name = "waydroid-vpn-disconnect";
      runtimeInputs = [ pkgs.curl pkgs.coreutils ];
      text = ''
        set -euo pipefail
        API="http://127.0.0.1:9090"

        if ! curl -fsS "$API/proxies/system-out" >/dev/null 2>&1; then
          echo "ОШИБКА: Clash API sing-box недоступен." >&2
          exit 1
        fi

        curl -fsS -X PUT "$API/proxies/system-out" \
          -H "Content-Type: application/json" \
          -d '{"name":"zapret-out"}' >/dev/null

        echo "Система вернулась в режим zapret-out (обход DPI)."
      '';
    })

    # Показать текущий режим и доступные outbound'ы selector'а.
    (pkgs.writeShellApplication {
      name = "waydroid-vpn-status";
      runtimeInputs = [ pkgs.curl pkgs.jq ];
      text = ''
        set -euo pipefail
        API="http://127.0.0.1:9090"

        if ! curl -fsS "$API/proxies/system-out" >/dev/null 2>&1; then
          echo "Clash API sing-box недоступен." >&2
          exit 1
        fi

        CURRENT=$(curl -fsS "$API/proxies/system-out" | jq -r '.now')
        echo "Текущий режим: $CURRENT"

        case "$CURRENT" in
          waydroid-out)
            echo "→ Весь трафик идёт через VPN (Waydroid)"
            ;;
          zapret-out)
            echo "→ Весь трафик идёт через zapret (обход DPI)"
            ;;
          *)
            echo "→ Неизвестный режим: $CURRENT"
            ;;
        esac

        echo
        echo "Доступные outbound'ы:"
        curl -fsS "$API/proxies/system-out" | jq -r '.all[]' | sed 's/^/  - /'
      '';
    })
  ];
}
