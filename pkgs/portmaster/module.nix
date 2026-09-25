{ config, lib, pkgs, ... }:

let
  cfg = config.services.portmaster;
in
{
  options.services.portmaster = {
    enable = lib.mkEnableOption "Portmaster application firewall";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Global settings for Portmaster, written to config.json.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/portmaster";
      description = "Directory where Portmaster stores its state and configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Устанавливаем пакет в системное окружение.
    environment.systemPackages = [ pkgs.portmaster ];

    # Загружаем модуль ядра, необходимый для перехвата трафика[reference:4].
    boot.kernelModules = [ "nfnetlink_queue" ];

    # Создаем systemd-сервис для Portmaster.
    systemd.services.portmaster = {
      description = "Portmaster Application Firewall";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # Запускаем portmaster-start, который управляет остальными компонентами.
        ExecStart = "${pkgs.portmaster}/bin/portmaster-start core --data ${cfg.stateDir}";
        Restart = "on-failure";
        RestartSec = "5";
        # Сервису нужны повышенные привилегии для работы с сетевым стеком.
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        # Создаем директорию для состояния при запуске.
        StateDirectory = "portmaster";
      };
    };
  };
}
