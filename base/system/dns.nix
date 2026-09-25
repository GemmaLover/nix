

{ config, lib, pkgs, ... }:

{
  # === ВРЕМЕННО: внешний DNS для bootstrap Portmaster ===
  # После того как Portmaster скачает свои компоненты,
  # вернём цепочку resolved -> Portmaster -> dnscrypt-proxy.

  # services.dnscrypt-proxy = { ... };        # отключено
  # services.resolved = { ... };               # отключено

  # Система использует внешний DNS напрямую.
  networking.nameservers = [ "9.9.9.9" "1.1.1.1" ];
  networking.networkmanager.dns = "none";

  # systemd-resolved отключён.
  services.resolved.enable = false;
}
