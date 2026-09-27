{
  config,
  lib,
  pkgs,
  ...
}: {
  # === Сеть ===
  # NetworkManager — управление Wi-Fi / Ethernet.
  networking.networkmanager.enable = true;

  # === nftables ===
  # Нужен для работы auto_route в sing-box и для перехвата трафика
  # в nfqws2 (zapret2). Без nftables auto_route не создаёт правила
  # fwmark, а nfqws2 не может получить пакеты через NFQUEUE.
  networking.nftables.enable = true;

  # === Firewall ===
  # Включаем. При networking.nftables.enable = true
  # firewall работает на nftables.
  networking.firewall = {
    enable = true;
    # Пусто — sing-box и nfqws2 сами управляют трафиком
    # через свои правила и NFQUEUE.
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # === Утилиты для отладки сети ===
  # nft — просмотр правил nftables (sudo nft list ruleset).
  # iptables — совместимость.
  # iproute2 — ip rule, ip route.
  # tcpdump — захват трафика.
  # dig — проверка DNS.
  environment.systemPackages = with pkgs; [
    nftables
    iptables
    iproute2
    tcpdump
    dig
  ];
}
