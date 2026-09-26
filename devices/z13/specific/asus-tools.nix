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
     (pkgs.callPackage ../../../pkgs/z13-fnlock { })
  ];

  # === Директория конфигурации ===
  # asusd требует наличия /etc/asusd для хранения конфигов.
  # Если директории нет — демон падает при старте.
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  # Установить Fn-Lock в режим "F1-F12 primary" при старте.
  # Отправляет HID feature report напрямую в N-Key клавиатуру,
  # потому что asusctl на GZ302EA не поддерживает fn_lock.
  systemd.services.asus-fnlock = {
    description = "Set ASUS Fn-Lock to F1-F12 primary (HID report)";
    wantedBy = [ "multi-user.target" ];
    # Запускать после загрузки системы — hidraw-устройства уже созданы.
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      # Небольшая задержка на случай, если hidraw ещё не готов.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = "${pkgs.callPackage ../../../pkgs/z13-fnlock { }}/bin/z13-fnlock on";
      RemainAfterExit = true;
      # Если клавиатура отключена — сервис не должен падать.
      SuccessExitStatus = [ 1 ];
    };
  };
}
