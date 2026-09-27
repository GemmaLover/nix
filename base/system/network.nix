{ config, lib, pkgs, ... }:

{
  # === Сеть ===
  # NetworkManager — управление сетевыми подключениями (Wi-Fi, Ethernet, VPN).
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
  # работает на nftables, а не на iptables-legacy.
  networking.firewall = {
    enable = true;
    # Разрешённые TCP-порты. Пусто — sing-box и Portmaster
    # сами управляют трафиком через свои правила.
    allowedTCPPorts = [ ];
    # Разрешённые UDP-порты. Пусто — аналогично.
    allowedUDPPorts = [ ];
  };

  # === Утилиты для отладки сети ===
  # nft — для просмотра правил nftables (sudo nft list ruleset).
  # iptables — совместимость с утилитами, которые его ожидают.
  # iproute2 — ip rule, ip route (обычно уже есть в системе).
  environment.systemPackages = with pkgs; [
    nftables
    iptables
    iproute2
  ];
}
