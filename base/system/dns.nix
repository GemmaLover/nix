{ config, lib, pkgs, ... }:

{
  services.dnscrypt-proxy = {
    enable = true;

    settings = {
      # Слушаем только IPv4. [::1]:53 занят Portmaster'ом,
      # а [::1]:5353 конфликтует с текущей конфигурацией.
      listen_addresses = [ "127.0.0.1:53" "127.0.0.1:5353" ];

      server_names = [
        "cloudflare"
        "quad9-dnscrypt-ip4-filter-pri"
        "scaleway-fr"
      ];

      require_dnssec = true;
      require_nolog = true;
      require_nofilter = true;

      ipv6_servers = false;
      block_ipv6 = true;

      # ОТКЛЮЧАЕМ HTTP/3 (DoH3, DNS-over-QUIC).
      # HTTP/3 использует UDP, который не проходит через TUN-интерфейс
      # sing-box (стек gvisor). Без этой опции dnscrypt-proxy будет
      # пытаться использовать DoH3, что приведёт к зависанию DNS.
      http3 = false;

      # ПРИНУДИТЕЛЬНО ИСПОЛЬЗУЕМ TCP.
      # Все зашифрованные DNS-запросы будут отправляться по TCP/443
      # (DoH2), а не по UDP. TCP через sing-box TUN работает надёжно.
      force_tcp = true;

      cache = true;
      cache_size = 4096;
    };
  };

  # Системный resolv.conf — только IPv4 loopback.
  networking.nameservers = [ "127.0.0.1" ];
  networking.networkmanager.dns = "none";
  services.resolved.enable = false;

  systemd.services.dnscrypt-proxy.serviceConfig.StateDirectory = "dnscrypt-proxy";
}
