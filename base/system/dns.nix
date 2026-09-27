{ config, lib, pkgs, ... }:

{
  services.dnscrypt-proxy = {
    enable = true;

    settings = {
      # listen_addresses: слушаем только IPv4 loopback.
      # [::1]:53 конфликтует с Portmaster (сейчас отключён),
      # но оставляем IPv4-only для простоты.
      listen_addresses = [ "127.0.0.1:53" "127.0.0.1:5353" ];

      # server_names: список DoH/DoT-резолверов.
      # cloudflare — 1.1.1.1
      # quad9 — 9.9.9.9 (без фильтрации)
      # scaleway — французский резолвер, хорошая альтернатива
      server_names = [
        "cloudflare"
        "quad9-dnscrypt-ip4-filter-pri"
        "scaleway-fr"
      ];

      require_dnssec = true;
      require_nolog = true;
      require_nofilter = true;

      # ipv6_servers = false: не используем IPv6 DNS-серверы.
      # block_ipv6 = true: не отдаём AAAA-записи клиентам.
      ipv6_servers = false;
      block_ipv6 = true;

      # http3 = false: ОТКЛЮЧАЕМ HTTP/3 (DoH3, DNS-over-QUIC).
      # HTTP/3 использует UDP, который не проходит через TUN-интерфейс
      # sing-box (стек gvisor). Без этой опции dnscrypt-proxy зависает
      # в SYN-SENT, DNS не работает, сайты не открываются.
      http3 = false;

      # force_tcp = true: принудительно TCP для всех DoH-запросов.
      # Гарантирует, что не будет попыток использовать UDP/QUIC.
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
