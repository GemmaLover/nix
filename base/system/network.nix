{ config, lib, pkgs, ... }:

{
  # === Сеть ===
  # NetworkManager — управление сетевыми подключениями (Wi-Fi, Ethernet, VPN)
  networking.networkmanager.enable = true;

  # === Firewall ===
  # Включаем файрвол, но разрешаем необходимые порты
  networking.firewall = {
    enable = true;
    # Разрешённые TCP-порты (пусто — будут добавлены по мере необходимости)
    allowedTCPPorts = [ ];
    # Разрешённые UDP-порты (пусто — будут добавлены по мере необходимости)
    allowedUDPPorts = [ ];
  };

}
