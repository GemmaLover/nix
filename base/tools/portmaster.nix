{ config, lib, pkgs, ... }:

{
  services.portmaster = {
    enable = true;
    settings = {
      "core/log/level" = "warning";
      "dns/nameservers" = [ "dns://127.0.0.1:5353" ];
      "dns/bootstrap-servers" = [ "dns://9.9.9.9" "dns://1.1.1.1" ];
    };
  };

  # Права на config.json выставляем отдельным oneshot-сервисом,
  # который запускается ПОСЛЕ того, как Portmaster создаст файл.
  # Так мы не блокируем сам portmaster.service.
  systemd.services.portmaster-config-fix = {
    description = "Make Portmaster config.json readable for GUI";
    after = [ "portmaster.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      # Ждём появления файла (макс. 60 секунд), потом chmod.
      ExecStart = "${pkgs.coreutils}/bin/sh -c 'for i in $(seq 1 60); do [ -f /var/lib/portmaster/config.json ] && break; sleep 1; done; chmod 644 /var/lib/portmaster/config.json 2>/dev/null || true'";
      RemainAfterExit = true;
    };
  };
}
