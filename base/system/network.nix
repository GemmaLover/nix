{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # Сеть: NetworkManager, firewall, nftables, MASQUERADE для sing-box TUN.
  #
  # Модель маршрутизации sing-box:
  #   1. sing-box создаёт TUN-интерфейс singtun0 (адрес 172.19.0.1/30).
  #   2. auto_route прописывает ip rule, который направляет весь
  #      исходящий трафик приложений (iif lo) в таблицу 2022,
  #      где default-маршрут ведёт на singtun0.
  #   3. sing-box читает пакеты из TUN и создаёт НОВОЕ исходящее
  #      соединение через физический интерфейс (wlp194s0).
  #   4. Поскольку source нового пакета — 172.19.0.1 (адрес TUN),
  #      MASQUERADE подменяет его на IP физического интерфейса
  #      (например, 192.168.1.194), иначе сервер не сможет
  #      ответить: адрес 172.19.0.1 в интернете не маршрутизируется.
  #   5. Ответ приходит на 192.168.1.194, sing-box его принимает
  #      и передаёт обратно в TUN — приложение получает ответ.
  #
  # Без MASQUERADE:
  #   - curl/Firefox висят в timeout,
  #   - в tcpdump видны только SYN'ы на singtun0,
  #     ни одного пакета на физическом интерфейсе.
  # =====================================================================

  # === NetworkManager ===
  # Управление сетевыми подключениями (Wi-Fi, Ethernet, VPN).
  networking.networkmanager.enable = true;

  # === nftables ===
  # nftables нужен для auto_route в sing-box 1.14.
  # В NixOS 26.11 при networking.nftables.enable = true
  # firewall тоже работает на nftables (через iptables-nft).
  networking.nftables.enable = true;

  # === Firewall ===
  # Порты не открываем: sing-box, Portmaster и dnscrypt
  # работают на loopback, входящий трафик извне им не нужен.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # =====================================================================
  # MASQUERADE для исходящих из TUN (sing-box).
  #
  # Проблема:
  #   Пакеты приложений попадают в TUN с source 172.19.0.1.
  #   sing-box читает их и создаёт исходящее соединение к серверу
  #   через физический интерфейс. Без MASQUERADE пакет уходит
  #   с source 172.19.0.1, который в интернете не маршрутизируется —
  #   ядро дропает его ещё до выхода на Wi-Fi, curl висит в timeout.
  #
  # Решение:
  #   MASQUERADE подменяет source на IP физического интерфейса
  #   (например, 192.168.1.194) в цепочке postrouting таблицы nat.
  #   Ответы возвращаются на реальный IP, sing-box их принимает
  #   и передаёт обратно в TUN — приложение получает ответ.
  #
  # Почему отдельная таблица singboxnat:
  #   Таблицы ip filter, ip mangle, ip nat уже используются
  #   Portmaster'ом и Docker'ом через iptables-nft. Объявление
  #   одной из них через networking.nftables.ruleset приведёт
  #   к конфликту. Создаём СВОЮ таблицу с уникальным именем.
  #
  # Почему priority 100:
  #   Стандартный приоритет для srcnat. Цепочка обрабатывается
  #   после filter-цепочек, но до того, как пакет уйдёт в сеть.
  #
  # Условие oifname != "singtun0":
  #   Не маскарадить трафик, уходящий обратно в TUN. Иначе
  #   sing-box подменит source собственных ответов, которые
  #   должны вернуться в приложение через TUN.
  # =====================================================================
  networking.nftables.ruleset = ''
    table ip singboxnat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 172.19.0.0/30 oifname != "singtun0" masquerade
      }
    }
  '';

  # === Утилиты для отладки сети ===
  # nft      — просмотр nftables (sudo nft list ruleset).
  # iptables — совместимость с утилитами, ожидающими iptables.
  # iproute2 — ip rule, ip route.
  # tcpdump  — анализ трафика (sudo tcpdump -i any ...).
  environment.systemPackages = with pkgs; [
    nftables
    iptables
    iproute2
    tcpdump
  ];
}
