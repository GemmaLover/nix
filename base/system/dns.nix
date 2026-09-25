{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # DNS-цепочка:
  #   система → 127.0.0.17:53 (Portmaster)
  #          → 127.0.0.1:5353 (dnscrypt-proxy)
  #          → DoH/DNSCrypt-резолверы (Cloudflare, Quad9, Scaleway)
  #
  # Portmaster слушает на 127.0.0.17 — специальном loopback-адресе,
  # чтобы 127.0.0.1:53 оставался свободным. Система должна обращаться
  # именно туда, иначе Portmaster не перехватит DNS.
  # =====================================================================

  # === dnscrypt-proxy ===
  # Слушает 5353, шифрует запросы к upstream через DoH/DNSCrypt.
  # Portmaster форвардит запросы сюда.
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:5353" "[::1]:5353" ];

      server_names = [
        "cloudflare"
        "quad9-dnscrypt-ip4-filter-pri"
        "scaleway-fr"
      ];

      require_dnssec = true;
      require_nolog = false;
      require_nofilter = false;

      ipv6_servers = false;
      block_ipv6 = true;

      cache = true;
      cache_size = 4096;
    };
  };

  # === Системный DNS ===
  # Система обращается к Portmaster'у на 127.0.0.17:53.
  # Portmaster, в свою очередь, форвардит запросы в dnscrypt-proxy.
  networking.nameservers = [ "127.0.0.17" ];
  networking.networkmanager.dns = "none";
  services.resolved.enable = false;

  # StateDirectory для кэша dnscrypt-proxy.
  systemd.services.dnscrypt-proxy.serviceConfig.StateDirectory = "dnscrypt-proxy";
}
