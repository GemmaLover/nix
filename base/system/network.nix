{ config, lib, pkgs, ... }:

{
  # === NetworkManager ===
  # Управление сетевыми подключениями (Wi-Fi, Ethernet, VPN).
  networking.networkmanager.enable = true;

  # === nftables ===
  # nftables нужен для работы auto_route в sing-box 1.14.
  #
  # Как это работает:
  #   1. sing-box создаёт TUN-интерфейс singtun0.
  #   2. Через nftables он маркирует пакеты, идущие от приложений,
  #      специальным fwmark.
  #   3. ip rule направляет помеченные пакеты в таблицу 2022,
  #      где default-маршрут указывает на singtun0.
  #   4. sing-box обрабатывает пакет и отправляет его через
  #      нужный outbound (direct, socks, vless).
  #   5. Через nftables sing-box исключает СВОИ СОБСТВЕННЫЕ
  #      исходящие пакеты из маркировки — иначе получается петля:
  #      пакет уходит в TUN → возвращается к sing-box → снова в TUN.
  #
  # Без nftables:
  #   - auto_route не создаёт правила fwmark,
  #   - прямые исходящие sing-box зацикливаются,
  #   - соединения зависают (curl: connection timed out).
  networking.nftables.enable = true;

  # === Firewall ===
  # Включаем firewall.
  # В NixOS 26.11 при networking.nftables.enable = true firewall
  # работает на nftables (через iptables-nft).
  networking.firewall = {
    enable = true;
    # Разрешённые TCP-порты. Пусто — sing-box и Portmaster
    # сами управляют трафиком через свои правила.
    allowedTCPPorts = [ ];
    # Разрешённые UDP-порты. Пусто — аналогично.
    allowedUDPPorts = [ ];

    # =====================================================================
    # MASQUERADE для исходящих из TUN (sing-box).
    #
    # Проблема:
    #   Пакеты от приложений попадают в TUN с source 172.19.0.1.
    #   sing-box читает их из TUN и создаёт исходящее соединение
    #   к серверу назначения через физический интерфейс (wlp194s0).
    #   Без MASQUERADE пакет уходит с source 172.19.0.1, который
    #   в интернете не маршрутизируется — ядро дропает его ещё
    #   до выхода на Wi-Fi. В tcpdump видно SYN'ы только на
    #   singtun0, но ни одного на wlp194s0, и curl висит в timeout.
    #
    # Решение:
    #   MASQUERADE подменяет source на IP физического интерфейса
    #   (например, 192.168.1.194) в цепочке POSTROUTING таблицы nat.
    #   После этого ответы от сервера возвращаются на реальный
    #   IP, sing-box их принимает и передаёт обратно в TUN —
    #   приложение получает ответ.
    #
    # Почему extraCommands, а не networking.nftables.ruleset:
    #   Таблицы ip/ip6 filter, mangle, nat уже управляются
    #   iptables-nft (Portmaster, Docker). Если попытаться
    #   объявить их через networking.nftables.ruleset, NixOS
    #   откажется из-за конфликта — правило не применится.
    #   extraCommands использует тот же iptables-nft и просто
    #   добавляет ещё одно правило к уже существующей цепочке
    #   POSTROUTING.
    #
    # Условие ! -o singtun0 — не маскарадить трафик, который
    # уходит обратно в TUN (иначе sing-box будет заворачивать
    # свои же ответы в TUN и получится петля).
    # =====================================================================
    extraCommands = ''
      iptables -t nat -A POSTROUTING \
        -s 172.19.0.0/30 \
        ! -o singtun0 \
        -j MASQUERADE
    '';

    # Убираем правило при остановке firewall, чтобы не оставалось
    # дубликатов при следующем запуске.
    extraStopCommands = ''
      iptables -t nat -D POSTROUTING \
        -s 172.19.0.0/30 \
        ! -o singtun0 \
        -j MASQUERADE 2>/dev/null || true
    '';
  };

  # === Утилиты для отладки сети ===
  # nft        — просмотр nftables (sudo nft list ruleset).
  # iptables   — совместимость и добавление MASQUERADE.
  # iproute2   — ip rule, ip route.
  # tcpdump    — анализ трафика (sudo tcpdump -i any ...).
  environment.systemPackages = with pkgs; [
    nftables
    iptables
    iproute2
    tcpdump
  ];
}
