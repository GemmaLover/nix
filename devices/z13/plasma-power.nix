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
      powerProfile = "balanced";

      # Экран гаснет через 20 минут (1200 секунд).
      turnOffDisplay.idleTimeout = 1200;

      # Автосон отключён: action = "nothing", idleTimeout = null.
      # Значение 0 недопустимо (диапазон 60..600000 или null).
      autoSuspend = {
        action = "nothing";
        idleTimeout = null;
      };
    };

    # Профиль при питании от батареи.
    battery = {
      powerProfile = "powerSaving";

      # Экран гаснет через 1 минуту (60 секунд).
      turnOffDisplay.idleTimeout = 60;

      # Уход в гибернацию через 5 минут (300 секунд).
      autoSuspend = {
        action = "hibernate";
        idleTimeout = 300;
      };
    };

    # Профиль при низком заряде батареи.
    lowBattery = {
      powerProfile = "powerSaving";
    };

    # Пороги батареи.
    batteryLevels = {
      lowLevel = 20;        # Считать батарею низкой при 20%.
      criticalLevel = 5;    # Критический уровень — 5%.
      criticalAction = "hibernate";  # Действие при критическом уровне.
    };
  };
}
