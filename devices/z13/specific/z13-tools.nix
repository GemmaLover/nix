{ config, lib, pkgs, ... }:

let
  # Подключаем локальные пакеты из pkgs/.
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

  # === Udev-правила ===
  # Правила из z13-tablet-kit дают доступ к устройствам ввода
  # (тачскрин, кнопка Armoury Crate) без root-прав.
  services.udev.packages = [ z13-tablet-kit ];

  # === Systemd user-сервис: демон z13ctl-plus ===
  # NixOS-синтаксис: unit-свойства и serviceConfig разделены.
  systemd.user.services.z13ctld = {
    description = "z13ctl-plus daemon for ASUS ROG Flow Z13";

    # Запускать после графической сессии и останавливать вместе с ней.
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${z13ctl-plus}/bin/z13ctl-plus daemon";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # === Systemd user-сервис: posture detection ===
  systemd.user.services.z13-tablet-switch = {
    description = "Z13 posture detection and tablet mode switch";

    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" "z13ctld.service" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${z13-tablet-kit}/bin/z13-tablet-switch";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # === Директория состояния ===
  # z13ctl-plus хранит настройки в $XDG_RUNTIME_DIR/z13ctl-plus/.
  systemd.tmpfiles.rules = [
    "d %t/z13ctl-plus 0700 %u %g -"
  ];
}
