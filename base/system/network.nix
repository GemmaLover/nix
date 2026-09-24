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

  # === Прокси ===
  # sing-box — универсальная прокси-платформа (настраивается отдельно)
  # Подробнее: https://wiki.nixos.org/wiki/Sing-box
  services.sing-box = {
    enable = true;
    settings = {
      # Настройки sing-box будут добавлены после предоставления конфигурации прокси
      # Пример конфигурации: см. https://sing-box.sagernet.org/configuration/
    };
  };
}
