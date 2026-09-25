{ config, lib, pkgs, ... }:

{
  imports = [
    # Импортируем наш локальный модуль.
    ../../pkgs/portmaster/module.nix
  ];

  # Включаем Portmaster с базовыми настройками.
  services.portmaster = {
    enable = true;
    settings = {
      "core/log/level" = "warning";
      # Указываем Portmaster использовать наш dnscrypt-proxy на порту 5353.
      "dns/nameservers" = [ "dns://127.0.0.1:5353" ];
    };
  };
}
