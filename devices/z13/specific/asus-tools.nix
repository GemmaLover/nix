{ config, lib, pkgs, ... }:

{
  # === ASUS-специфичные утилиты ===
  # Установка asusctl для управления подсветкой клавиатуры и производительностью
  # Источник: https://gitlab.com/asus-linux/asusctl

  # asusctl — CLI для управления ASUS ROG/TUF ноутбуками
  # Включает: подсветка клавиатуры, лимиты заряда, профили производительности
  environment.systemPackages = with pkgs; [
    asusctl
    # supergfxctl — переключение GPU (для ноутбуков с двумя GPU)
    # supergfxctl
  ];

  # Сервис asusd — демон для управления ASUS-специфичным оборудованием
  systemd.services.asusd = {
    enable = true;
    description = "ASUS ROG/TUF control daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.asusctl}/bin/asusd";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # Сервис asusd-user — пользовательский сервис для управления подсветкой
  systemd.user.services.asusd-user = {
    enable = true;
    description = "ASUS ROG/TUF user control daemon";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.asusctl}/bin/asusd-user";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # === Скрипты для управления подсветкой ===
  # Подсветка клавиатуры отключается через 15 секунд простоя.
  # Скрипт будет добавлен в base/system/scripts/
  # Подробнее: см. base/system/scripts/keyboard-backlight.sh
}
