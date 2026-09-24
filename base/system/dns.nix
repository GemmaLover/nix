{ config, lib, pkgs, ... }:

{
  # === Шифрование DNS через DNSCrypt-proxy2 ===
  services.dnscrypt-proxy2 = {
    enable = true;

    settings = {
      # Слушаем только на localhost.
      listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];

      # === Явный список резолверов ===
      # Конкретные доверенные резолверы с DNSSEC.
      # dnscrypt-proxy2 знает их параметры из встроенной базы.
      server_names = [
        "cloudflare"                          # Cloudflare DNS (DoH)
        "quad9-dnscrypt-ip4-filter-pri"      # Quad9 (DNSCrypt, фильтрация malware)
        "scaleway-fr"                         # Scaleway (DNSCrypt)
      ];

      # Требовать DNSSEC.
      require_dnssec = true;

      # Не требовать отсутствия логов (некоторые резолверы ведут логи для отладки).
      require_nolog = false;

      # Не требовать отсутствия фильтрации (Quad9 фильтрует malware).
      require_nofilter = false;

      # Отключаем IPv6-резолверы.
      ipv6_servers = false;

      # Блокировать IPv6-запросы.
      block_ipv6 = true;

      # Кэш.
      cache = true;
      cache_size = 4096;
    };
  };

  # === Системный DNS ===
  networking.nameservers = [ "127.0.0.1" "::1" ];
  networking.networkmanager.dns = "none";
  services.resolved.enable = false;

  # StateDirectory для кэша.
  systemd.services.dnscrypt-proxy2.serviceConfig.StateDirectory = "dnscrypt-proxy";
}
