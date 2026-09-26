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

    # Установить fn-lock в режим "F1-F12 primary" при старте.
  systemd.services.asus-fnlock = {
    description = "Set ASUS fn-lock to F1-F12 primary";
    wantedBy = [ "multi-user.target" ];
    after = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.asusctl}/bin/asusctl fn-lock -s true";
      RemainAfterExit = true;
    };
  };
}
