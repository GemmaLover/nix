{ config, lib, pkgs, ... }:

let
  # Подключаем локальные пакеты.
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

  # === Systemd-сервис для демона z13ctl-plus ===
  # Демон управляет состоянием дисплея, подсветкой, профилями.
  # Запускается как пользовательский сервис, потому что ему нужен
  # доступ к Wayland-сессии (kscreen-doctor).
  systemd.user.services.z13ctld = {
    Unit = {
      Description = "z13ctl-plus daemon for ASUS ROG Flow Z13";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${z13ctl-plus}/bin/z13ctld";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # === Systemd-сервис для z13-tablet-switch ===
  # Следит за положением устройства (док/фолио/планшет)
  # и переключает режимы через D-Bus.
  systemd.user.services.z13-tablet-switch = {
    Unit = {
      Description = "Z13 posture detection and tablet mode switch";
      After = [ "graphical-session.target" "z13ctld.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${z13-tablet-kit}/bin/z13-tablet-switch";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # === Директория состояния ===
  # z13ctl-plus хранит настройки в $XDG_RUNTIME_DIR/z13ctl-plus/.
  # Создаём её через tmpfiles, чтобы демон не падал.
  systemd.tmpfiles.rules = [
    "d %t/z13ctl-plus 0700 %u %g -"
  ];
}
