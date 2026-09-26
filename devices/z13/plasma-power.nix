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

            # При закрытии крышки от сети — ничего не делать.
      whenLaptopLidClosed = "doNothing";

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

            # При закрытии крышки от батареи — заблокировать пользователя.
      # Экран выключится сразу после блокировки (см. turnOffDisplay ниже).
      whenLaptopLidClosed = "lockScreen";

      # Уход в гибернацию через 5 минут (300 секунд).
      autoSuspend = {
        action = "hibernate";
        idleTimeout = 300;
      };
    };

    # Профиль при низком заряде батареи.
    lowBattery = {
      powerProfile = "powerSaving";

            # При закрытии крышки от батареи — заблокировать пользователя.
      # Экран выключится сразу после блокировки (см. turnOffDisplay ниже).
      whenLaptopLidClosed = "lockScreen";
    };

        # --- Немедленное выключение экрана при блокировке ---
    # KDE имеет баг: при выборе «lockScreen» при закрытии крышки
    # подсветка не гаснет. Эта настройка заставляет экран гаснуть
    # сразу после блокировки.
    turnOffDisplay.idleTimeoutWhenLocked = "immediately";

        # Не подавлять действие при подключённом внешнем мониторе
    # (если хотите, чтобы при закрытии крышки с внешним монитором
    #  действие всё равно срабатывало).
    # inhibitLidActionWhenExternalMonitorConnected = false;

    # Пороги батареи.
    batteryLevels = {
      lowLevel = 20;        # Считать батарею низкой при 20%.
      criticalLevel = 5;    # Критический уровень — 5%.
      criticalAction = "hibernate";  # Действие при критическом уровне.
    };
  };

  # =====================================================================
  # Настройки ввода (тачпад) через plasma-manager.
  #
  # KDE на Wayland игнорирует services.libinput.touchpad.disableWhileTyping,
  # потому что управляет настройками ввода сам. plasma-manager пишет
  # нужные значения в ~/.config/kcminputrc — оттуда KDE их читает.
  #
  # vendorId и productId — обязательные поля. По ним KDE идентифицирует
  # конкретное устройство. Без них plasma-manager падает с ошибкой
  # "vendorId is not of type string".
  #
  # Значения взяты из `udevadm info` для GZ302EA-Keyboard Touchpad:
  #   ID_VENDOR_ID=0b05  (ASUSTeK)
  #   ID_MODEL_ID=1a30   (GZ302EA-Keyboard)
  # =====================================================================
  programs.plasma.input.touchpads = [
    {
      # plasma-manager требует hex-код БЕЗ префикса "0x" —
      # ровно 4 hex-цифры. Значения из `udevadm info`:
      #   ID_VENDOR_ID=0b05  (ASUSTeK)
      #   ID_MODEL_ID=1a30   (GZ302EA-Keyboard)
      vendorId = "0b05";
      productId = "1a30";
      name = "ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad";

      disableWhileTyping = true;
      tapToClick = true;
      naturalScroll = true;
      scrollMethod = "twoFinger";
    }
  ];
}
