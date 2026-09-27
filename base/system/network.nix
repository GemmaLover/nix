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
  # Нужен для работы auto_route в sing-box 1.14.
  # Без nftables auto_route не создаёт правила fwmark,
  # прямые исходящие sing-box зацикливаются, соединения зависают.
  networking.nftables.enable = true;

  # === Firewall ===
  # Включаем. При networking.nftables.enable = true
  # firewall работает на nftables.
  networking.firewall = {
    enable = true;

    # Пусто — sing-box и byedpi сами управляют трафиком
    # через свои правила и локальные сокеты.
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
