{
  config,
  lib,
  pkgs,
  ...
}: {
  # === Сеть ===
  # NetworkManager — управление сетевыми подключениями (Wi-Fi, Ethernet, VPN).
  networking.networkmanager.enable = true;

  # === nftables ===
  # nftables нужен для работы auto_route в sing-box 1.14.
  #
  # Как это работает:
  # 1. sing-box создаёт TUN-интерфейс singtun0.
  # 2. Через nftables он маркирует пакеты, идущие от приложений,
  #    специальным fwmark.
  # 3. ip rule направляет помеченные пакеты в таблицу 2022,
  #    где default-маршрут указывает на singtun0.
  # 4. sing-box обрабатывает пакет и отправляет его через
  #    нужный outbound (direct, socks, vless).
  # 5. Через nftables sing-box исключает СВОИ СОБСТВЕННЫЕ
  #    исходящие пакеты из маркировки — иначе получается петля:
  #    пакет уходит в TUN → возвращается к sing-box → снова в TUN.
  #
  # Без nftables:
  # - auto_route не создаёт правила fwmark,
  # - прямые исходящие sing-box зацикливаются,
  # - соединения зависают (curl: connection timed out).
  networking.nftables.enable = true;

  # === Firewall ===
  # Включаем firewall.
  # В NixOS 26.11 при networking.nftables.enable = true firewall
  # работает на nftables, а не на iptables-legacy.
  networking.firewall = {
    enable = true;

    # Разрешённые TCP-порты. Пусто — sing-box и Portmaster
    # сами управляют трафиком через свои правила.
    allowedTCPPorts = [];

    # Разрешённые UDP-порты. Пусто — аналогично.
    allowedUDPPorts = [];
  };

  # === nftables: обход nfqueue Portmaster для трафика sing-box ===
  #
  # ПРОБЛЕМА (подтверждена экспериментально):
  # Portmaster перехватывает все пакеты с mark=0 через nfqueue.
  # Его правило в iptables-nft:
  #   meta mark 0x00000000 counter queue num 17040 bypass
  # (цепочка PORTMASTER-INGEST-OUTPUT, таблица ip mangle).
  #
  # У сокета sing-box стоит fwmark 0x2023 (видно через ss -tnp -e).
  # Значит исходящие SYN-пакеты sing-box уходят с mark 0x2023,
  # и Portmaster их НЕ перехватывает (его правило ищет mark == 0).
  #
  # НО: fwmark на сокете влияет только на ИСХОДЯЩИЕ пакеты.
  # Ответные пакеты от сервера (SYN-ACK, данные) приходят
  # в систему с mark=0. Portmaster их перехватывает через
  # nfqueue, анализирует, и пакет возвращается в сетевой стек
  # С ЗАДЕРЖКОЙ или с изменённым состоянием.
  #
  # Результат:
  #  - sing-box открывает исходящее соединение (ESTAB в ss),
  #  - но ответ от сервера не доходит до sing-box вовремя,
  #  - Firefox ждёт → таймаут → «сайт не открывается».
  #
  # Почему «старые сайты работают, новые нет»:
  #  - для уже установленных соединений ответы идут по conntrack
  #    быстро, Portmaster их пропускает без задержки;
  #  - для новых соединений Portmaster перехватывает SYN-ACK
  #    и создаёт заметную задержку → таймаут.
  #
  # РЕШЕНИЕ:
  # Распространить mark 0x2023 на ВЕСЬ conntrack sing-box
  # через ct mark (conntrack mark — метка на уровне ядра,
  # автоматически проставляется на всех пакетах соединения,
  # в обе стороны).
  #
  # Логика:
  #  1. Цепочка output (hook output, priority -155):
  #     На исходящих пакетах sing-box (meta mark 0x2023)
  #     ставим ct mark 0x2023. Это создаёт conntrack-запись
  #     с меткой 0x2023 для всего соединения.
  #  2. Цепочка prerouting (hook prerouting, priority -155):
  #     На ВХОДЯЩИХ пакетах, у которых ct mark == 0x2023
  #     (то есть ответах от сервера для соединений sing-box),
  #     ставим meta mark 0x2023.
  #  3. Теперь Portmaster видит у ответных пакетов mark != 0
  #     и НЕ перехватывает их через nfqueue.
  #
  # ПОЧЕМУ priority -155:
  # Portmaster использует iptables-nft, его цепочки находятся
  # в таблице ip mangle с приоритетом -150.
  # Наш priority -155 < -150, значит наши правила срабатывают
  # РАНЬШЕ, чем Portmaster посмотрит на пакет.
  # Это критично: мы должны проставить mark до того, как
  # Portmaster примет решение перехватывать или нет.
  #
  # ВАЖНО ПРО ПЕРЕСБОРКУ:
  # После каждого nixos-rebuild switch nftables.service
  # перезаписывает ruleset целиком. Portmaster теряет свои
  # правила (iptables-nft таблицы сносятся). Это не связано
  # с нашей таблицей singbox-bypass — так было и до неё.
  # Восстановить: sudo systemctl restart portmaster
  #
  # Проверка после пересборки:
  #   sudo nft list table ip singbox-bypass
  #   sudo conntrack -L 2>/dev/null | grep "mark=0x2023"
  networking.nftables.ruleset = ''
    # Таблица ip singbox-bypass: помечает ответные пакеты
    # соединений sing-box, чтобы они обходили nfqueue Portmaster.
    table ip singbox-bypass {
      # Цепочка output: ставит ct mark на исходящие пакеты sing-box.
      # Срабатывает в момент отправки пакета из локального процесса.
      # meta mark 0x2023 — это fwmark, который sing-box ставит
      # на свои исходящие сокеты (через default_mark = 8227).
      # ct mark set 0x2023 — «приклеивает» этот же mark ко всему
      # conntrack-соединению, включая будущие ответные пакеты.
      chain output {
        type mangle hook output priority -155; policy accept;
        meta mark 0x2023 ct mark set 0x2023
      }

      # Цепочка prerouting: восстанавливает meta mark на входящих
      # пакетах по ct mark. Это ключевой шаг: ответ от сервера
      # приходит с mark=0, но у него в conntrack записан mark 0x2023.
      # Мы ставим meta mark 0x2023 на такой пакет, и Portmaster
      # его пропускает (его nfqueue-правило ищет mark == 0).
      chain prerouting {
        type mangle hook prerouting priority -155; policy accept;
        ct mark 0x2023 meta mark set 0x2023
      }
    }
  '';

  # === Утилиты для отладки сети ===
  # nft — для просмотра правил nftables (sudo nft list ruleset).
  # iptables — совместимость с утилитами, которые его ожидают.
  # iproute2 — ip rule, ip route (обычно уже есть в системе).
  # tcpdump — для захвата и анализа сетевого трафика.
  # dig — для проверки DNS-резолвинга.
  environment.systemPackages = with pkgs; [
    nftables
    iptables
    iproute2
    tcpdump
    dig
  ];
}
