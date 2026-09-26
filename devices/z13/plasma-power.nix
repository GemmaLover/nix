{ config, pkgs, ... }:

{
  # =====================================================================
  # Автоматическое переключение профилей PowerDevil (KDE) при смене питания.
  #
  # PowerDevil передаёт выбранный профиль в power-profiles-daemon (PPD).
  # Наш сервис z13-ppd-sync слушает PPD и применяет TDP + кулеры через z13ctl.
  #
  # Цепочка:
  #   KDE PowerDevil → PPD → z13-ppd-sync → z13ctl
  #
  # Значения powerProfile:
  #   performance   → PPD "performance"
  #   balanced      → PPD "balanced"
  #   powerSaving   → PPD "power-saver"
  # =====================================================================

  programs.plasma.powerdevil = {
    # Профиль при питании от сети.
    AC = {
     # Экран гаснет через 20 минут (1200 секунд).
      turnOffDisplay.idleTimeout = 1200;
      # Сон отключён.
      autoSuspend = {
        action = "nothing";
        idleTimeout = 0;
      };

      powerProfile = "balanced";
      # Остальные настройки (яркость, засыпание) — оставляем по умолчанию.
    };

    # Профиль при питании от батареи.
    battery = {
      powerProfile = "powerSaving";

       # Экран гаснет через 1 минуту (60 секунд).
      turnOffDisplay.idleTimeout = 60;


      autoSuspend = {
        action = "hibernate";
        idleTimeout = 300;
      };
    };

    # Профиль при низком заряде батареи.
    lowBattery = {
      powerProfile = "powerSaving";
    };

    # Пороги батареи (необязательно, но полезно).
    batteryLevels = {
      lowLevel = 20;        # Считать батарею низкой при 20%.
      criticalLevel = 5;    # Критический уровень — 5%.
      criticalAction = "hibernate";  # Действие при критическом уровне.
    };
  };



}
