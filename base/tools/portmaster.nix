{ config, lib, pkgs, ... }:

{
  services.portmaster = {
    enable = true;

    settings = {
      # Уровень логирования.
      "core/log/level" = "warning";

      # Portmaster форвардит DNS-запросы в dnscrypt-proxy.
      # dnscrypt-proxy шифрует их и отправляет к DoH/DNSCrypt-резолверам.
      "dns/nameservers" = [ "dns://127.0.0.1:5353" ];

      # Bootstrap-DNS: используется только один раз при первом запуске,
      # когда Portmaster скачивает свои компоненты.
      # После первой загрузки значение можно убрать.
      # Пока оставляем как страховку.
      "dns/bootstrap-servers" = [ "dns://9.9.9.9" "dns://1.1.1.1" ];
    };
  };

  # Portmaster-core создаёт config.json с правами 0600 (root-only).
  # GUI работает от пользователя lexi и не может его прочитать.
  # ExecStartPost делает файл читаемым для всех после старта сервиса.
  systemd.services.portmaster.serviceConfig.ExecStartPost = [
    "${pkgs.coreutils}/bin/chmod 644 /var/lib/portmaster/config.json"
  ];

  # Portmaster должен стартовать после сети и после dnscrypt-proxy,
  # чтобы сразу найти upstream.
  systemd.services.portmaster = {
    after = [ "network-online.target" "dnscrypt-proxy.service" ];
    wants = [ "network-online.target" "dnscrypt-proxy.service" ];
  };
}
