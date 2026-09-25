{ config, lib, pkgs, ... }:

let
  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };
  z13gui-plus = pkgs.callPackage ../../../pkgs/z13gui-plus { };
  z13-tablet-kit = pkgs.callPackage ../../../pkgs/z13-tablet-kit { };
in
{
  # === Пакеты ===
  environment.systemPackages = [
    z13ctl-plus
    z13gui-plus
    z13-tablet-kit
  ];

  # === Udev-правила из z13-tablet-kit ===
  services.udev.packages = [ z13-tablet-kit ];

  # === Systemd user-сервис: демон z13ctl ===
  # Запускает `z13ctl daemon` — следит за Armoury Crate button,
  # posture detection и управлением подсветкой через hidraw.
  systemd.user.services.z13ctld = {
    description = "z13ctl device daemon for ASUS ROG Flow Z13";

    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${z13ctl-plus}/bin/z13ctl daemon";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # === Директория состояния ===
  systemd.tmpfiles.rules = [
    "d %t/z13ctl 0700 %u %g -"
  ];
}
