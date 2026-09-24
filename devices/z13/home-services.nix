{ config, pkgs, ... }:

{
  # === Пользовательские systemd-сервисы для z13 ===

  # Настройка подсветки клавиатуры: статичный белый цвет, низкая яркость.
  # Запускается при входе в графическую сессию.
  # Подсветка без пульсации — режим Static вместо Breathe/Pulse.
  systemd.user.services.asus-keyboard-backlight = {
    Unit = {
      Description = "Set ASUS keyboard backlight to static white at low brightness";
      # После входа в графическую сессию, когда пользователь уже в KDE.
      After = [ "graphical-session.target" ];
      # Часть графической сессии — останавливается вместе с ней.
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # oneshot — выполнить команды один раз и завершиться.
      Type = "oneshot";
      # Устанавливаем статичный белый цвет.
      # aura effect static — режим без анимации.
      # -c ffffff — белый цвет в HEX.
      ExecStart = [
        "${pkgs.asusctl}/bin/asusctl aura effect static -c ffffff"
        "${pkgs.asusctl}/bin/asusctl leds set low"
      ];
      # Оставить сервис в состоянии active (exited) после завершения.
      RemainAfterExit = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Отключение подсветки через 15 секунд простоя.
  # swayidle отслеживает активность Wayland (клавиатура, тачпад, мышь).
  systemd.user.services.swayidle-backlight = {
    Unit = {
      Description = "Turn off keyboard backlight after 15s idle";
      # Запускать после настройки цвета.
      After = [ "graphical-session.target" "asus-keyboard-backlight.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # swayidle -w — ждать завершения команд.
      # timeout 15 — через 15 секунд простоя выключить подсветку.
      # resume — вернуть низкую яркость при возобновлении активности.
      ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 15 '${pkgs.asusctl}/bin/asusctl leds set off' resume '${pkgs.asusctl}/bin/asusctl leds set low'";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
