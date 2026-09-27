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
  # │ - dnscrypt-proxy → direct                                    │
  # │ - Chromium → vless-out                                       │
  # │ - Всё остальное (Firefox, Brave и т.д.) → zapret-out         │
  # └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  # - routing_mark = 110 в OUTBOUND — это правильный способ
  #   помечать пакеты для nfqws2. В TUN inbound такой опции НЕТ.
  # - default_mark = 8227 — помечает все исходящие сокеты sing-box
  #   (для разрыва петли через TUN). Это отдельная метка,
  #   она НЕ связана с routing_mark = 110.
  # - stack = "gvisor" — КРИТИЧНО.
  #   sing-box терминирует TCP в userspace и открывает НОВЫЙ сокет
  #   от имени системы с src=физический IP. MASQUERADE не нужен.
  #   "mixed" и "system" ломают TCP через TUN без MASQUERADE.
  # - auto_redirect ОТКЛЮЧЁН. Используем auto_route.
  # - sniff на inbound в sing-box 1.14 УБРАН.
  # =====================================================================
  services.sing-box = {
    enable = true;
    settings = {
      # log.level: info — штатный режим. debug включать только для отладки.
      log = {
        level = "info";
      };

      # =================================================================
      # INBOUND: TUN-интерфейс singtun0.
      # sing-box создаёт виртуальный сетевой интерфейс, через который
      # проходит весь трафик приложений, направленный в TUN.
      # =================================================================
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";

          # address: IPv4 + IPv6 префиксы для TUN-интерфейса.
          # IPv6 (ULA fdfe:...) нужен, чтобы заворачивать IPv6-трафик.
          address = [
            "172.19.0.1/30"
            "fdfe:dcba:9876::1/126"
          ];

          # dns_mode = "disabled": sing-box НЕ перехватывает DNS.
          # DNS обслуживает связка dnscrypt-proxy → DoH.
          # Без этой опции sing-box создаст свой DNS-прокси,
          # что приведёт к конфликту с dnscrypt-proxy.
          dns_mode = "disabled";

          # auto_route: создаёт ip rule + таблицу 2022 для TUN.
          # Без него трафик не будет заворачиваться в TUN автоматически.
          auto_route = true;

          # strict_route = false: совместимость с локальными сервисами
          # (dnscrypt-proxy, nfqws2 слушают на 127.0.0.1).
          # true ломает localhost-соединения.
          strict_route = false;

          # MTU TUN-интерфейса.
# 1280 — безопасное значение для IPv6 и для raw socket в nfqws2.
# 1400 вызывал ошибки "Message too long" в nfqws2 при отправке
# десинхронизированных пакетов через raw socket.
mtu = 1280;

          # stack = "gvisor": TCP termination в userspace.
          # sing-box сам открывает новый сокет → MASQUERADE не нужен.
          # Это единственный рабочий вариант для TUN без MASQUERADE.
          stack = "gvisor";
        }
      ];

      # =================================================================
      # OUTBOUNDS: куда sing-box направляет трафик.
      # =================================================================
      outbounds = [
        # --- socks-out: внешний SOCKS5 (резервный) ---
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";
          server_port = 1080;
          version = "5";
          username = "chelik";
          password = "pass11";
        }

        # --- zapret-out: специальный outbound для nfqws2 ---
        # type "direct" + routing_mark = 110.
        # sing-box просто помечает трафик этим mark'ом,
        # а nftables (таблица zapret_nfqws2) перенаправляет
        # помеченные пакеты в очередь NFQUEUE (num 200),
        # где их обрабатывает nfqws2 с Lua-стратегиями.
        #
        # Это НЕ проксирование, а "стикер" на пакете.
        {
          type = "direct";
          tag = "zapret-out";
          routing_mark = 110;
        }

        # --- vless-out: VLESS с XTLS-Vision (для Chromium) ---
        # Полноценный прокси на удалённый сервер.
        # Трафик шифруется и уходит через VLESS-туннель.
        {
          type = "vless";
          tag = "vless-out";
          server = "ВАШ_СЕРВЕР";
          server_port = 443;
          uuid = "ВАШ_UUID";
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН";
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }

        # --- direct-out: выход напрямую через физический интерфейс ---
        # Без проксирования, без обхода DPI. Просто системный стек.
        {
          type = "direct";
          tag = "direct-out";
        }
      ];

      # =================================================================
      # ROUTE: правила маршрутизации трафика между outbound'ами.
      #
      # Порядок правил ВАЖЕН: правила проверяются сверху вниз,
      # первое совпадение выигрывает.
      # =================================================================
      route = {
        # find_process: определять процесс по сокету (для process_name).
        find_process = true;

        # auto_detect_interface: автоматически выбрать физический
        # интерфейс для выхода (wlp194s0, eth0 и т.п.).
        auto_detect_interface = true;

        # default_mark = 8227 (0x2023): помечает ВСЕ исходящие сокеты
        # sing-box. Правило ip rule priority 100 (сервис
        # sing-box-fwmark-rule) направляет эти пакеты через main-таблицу
        # маршрутизации, разрывая петлю sing-box → TUN → sing-box.
        #
        # ЭТО НЕ ТО ЖЕ САМОЕ, ЧТО routing_mark = 110 у zapret-out.
        # 8227 — защита от петли через TUN.
        # 110 — метка для nfqws2.
        default_mark = 8227;

        # -------------------------------------------------------------
        # Правила маршрутизации.
        # -------------------------------------------------------------
        rules = [
          # 1. Локальные адреса — всегда direct.
          #    127.0.0.0/8 и ::1/128 — loopback. Трафик к ним
          #    не должен попадать ни в TUN, ни в nfqws2.
          {
            ip_cidr = ["127.0.0.0/8" "::1/128"];
            outbound = "direct-out";
          }

          # 2. dnscrypt-proxy — direct (без nfqws2).
          #    DNS-резолвер должен ходить к DoH-серверам
          #    напрямую, без десинхронизации и без mark 110.
          #    Иначе DNS-запросы будут ломаться nfqws2.
          {
            process_name = ["dnscrypt-proxy"];
            outbound = "direct-out";
          }

          # 3. NTP (UDP/123) — direct.
          #    systemd-timesyncd не должен идти через TUN/nfqws2.
          {
            network = "udp";
            port = [123];
            outbound = "direct-out";
          }

          # 4. Chromium → VLESS (без nfqws2).
          #    Chromium использует полноценный прокси через VLESS,
          #    ему не нужен локальный обход DPI.
          {
            process_name = ["chromium"];
            outbound = "vless-out";
          }
          {
            process_path_regex = [".*/chromium/chromium.*"];
            outbound = "vless-out";
          }

          # 5. Fallback: всё остальное → zapret-out.
          #    В том числе Firefox и Brave, которые пойдут через nfqws2.
          #    sing-box поставит mark 110, nftables перехватит
          #    первые 6 пакетов каждого соединения в NFQUEUE 200.
          {
            outbound = "zapret-out";
          }
        ];
      };
    };
  };

  # =====================================================================
  # Capabilities и PATH для sing-box.
  #
  # CAP_NET_ADMIN — работа с TUN и ip rule.
  # CAP_NET_RAW — работа с сокетами низкого уровня.
  # CAP_NET_BIND_SERVICE — привязка к привилегированным портам.
  # CAP_SYS_PTRACE — определение процесса по сокету (find_process).
  # =====================================================================
  systemd.services.sing-box.serviceConfig = {
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
    path = [pkgs.nftables pkgs.iptables pkgs.iproute2];
  };

  # =====================================================================
  # Правила маршрутизации для fwmark 0x2023 (IPv4 + IPv6).
  #
  # ЗАЧЕМ ЭТО НУЖНО:
  # default_mark = 8227 у sing-box помечает все исходящие сокеты.
  # Но ядро само по себе не знает, что делать с этой меткой —
  # нужно явно указать: "пакеты с mark 8227 смотри в main-таблице".
  #
  # Без этого правила пакет с mark 8227 всё равно пойдёт
  # по auto_route (правило 9001) в TUN → петля.
  #
  # priority 100 — выше auto_route (9000-9010), поэтому срабатывает
  # раньше и выводит пакеты sing-box из петли через TUN.
  #
  # Идемпотентность: сначала удаляем старые правила (если есть),
  # затем добавляем новые. Без этого рестарт сервиса падал бы
  # с "RTNETLINK answers: File exists".
  #
  # Нужны ДВА правила (IPv4 и IPv6):
  #  - IPv4: для стандартных соединений sing-box.
  #  - IPv6: для DoH/QUIC-соединений, которые dnscrypt-proxy
  #    открывает через IPv6.
  # =====================================================================
  systemd.services.sing-box-fwmark-rule = {
    description = "Add ip rule for sing-box default_mark (break TUN loop, v4+v6)";
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # ExecStop — отдельный shell-скрипт, чтобы `|| true` работал.
      # Запускается при остановке/рестарте юнита.
      ExecStop = pkgs.writeShellScript "sing-box-fwmark-stop" ''
        ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      '';
    };

    # script → NixOS оборачивает в bash. Идемпотентное добавление.
    script = ''
      # Шаг 1: удаляем возможные старые правила (без ошибок).
      ${pkgs.iproute2}/bin/ip    rule del fwmark 8227 lookup main priority 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del fwmark 8227 lookup main priority 100 2>/dev/null || true

      # Шаг 2: добавляем свежие правила.
      ${pkgs.iproute2}/bin/ip    rule add fwmark 8227 lookup main priority 100
      ${pkgs.iproute2}/bin/ip -6 rule add fwmark 8227 lookup main priority 100
    '';
  };
}
