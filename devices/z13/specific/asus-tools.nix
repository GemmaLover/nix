{ config, lib, pkgs, ... }:

{
  # === ASUS-специфичные утилиты ===
  # Используем встроенный модуль NixOS services.asusd вместо ручного
  # создания systemd-сервисов. Модуль корректно настраивает зависимости,
  # порядок запуска и D-Bus-политику.
  services.asusd = {
    enable = true;
    # enableUserService = true;  # ОТКЛЮЧЕНО: вызывает панику asusd-user
    # при отсутствии поддержки AniMe Matrix на Z13.
    # Для управления подсветкой клавиатуры достаточно системного asusd.
  };

  # asusctl CLI для ручного управления (подсветка, профили, лимиты заряда).
  environment.systemPackages = with pkgs; [
    asusctl
  ];

  # === Директория конфигурации ===
  # asusd требует наличия /etc/asusd для хранения конфигов.
  # Если директории нет — демон падает при старте.
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];
}
