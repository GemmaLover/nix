{ config, lib, pkgs, ... }:

let
  cfg = config.services.portmaster;

  # Подтягиваем локальный пакет из default.nix, лежащего рядом.
  # callPackage автоматически передаст все зависимости, объявленные
  # в аргументах функции в default.nix (buildGoModule, fetchFromGitHub и т.д.).
  portmaster = pkgs.callPackage ./default.nix { };
in
{
  options.services.portmaster = {
    enable = lib.mkEnableOption "Portmaster application firewall";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Global settings for Portmaster, written to config.json.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/portmaster";
      description = "Directory where Portmaster stores its state and configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Устанавливаем локальный пакет в системное окружение.
    environment.systemPackages = [ portmaster ];

    # Модуль ядра для перехвата трафика через nfqueue.
    boot.kernelModules = [ "nfnetlink_queue" ];

    systemd.services.portmaster = {
      description = "Portmaster Application Firewall";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # Используем локальный portmaster, а не pkgs.portmaster.
        ExecStart = "${portmaster}/bin/portmaster-start core --data ${cfg.stateDir}";
        Restart = "on-failure";
        RestartSec = "5";

        # Сервису нужны повышенные привилегии для работы с сетевым стеком.
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];

        StateDirectory = "portmaster";
      };
    };
  };
}
