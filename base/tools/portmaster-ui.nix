{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # Автозапуск Portmaster Notifier (иконка в системном трее).
  #
  # Это Home Manager-модуль — подключается из devices/z13/home.nix.
  # Системный сервис ядра Portmaster (portmaster.service) описан в
  # base/tools/portmaster.nix и подключается из devices/z13/config.nix.
  #
  # Notifier — лёгкий пользовательский процесс, отображает иконку
  # в трее и открывает основной UI по клику. Запускается после
  # graphical-session.target, живёт, пока активна сессия.
  # =====================================================================
  systemd.user.services.portmaster-notifier = {
    Unit = {
      Description = "Portmaster Notifier (system tray icon)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      # portmaster-start notifier — запускает именно Notifier, а не UI.
      ExecStart = "${pkgs.portmaster}/bin/portmaster-start notifier";
      Restart = "on-failure";
      RestartSec = "10";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
