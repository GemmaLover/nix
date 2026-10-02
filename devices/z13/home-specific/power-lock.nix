{ config, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/power-lock.nix — настройки PLASMA для z13:
  # питание, блокировка, тачпад (подключается только при kda.opts.ui="kde",
  # см. default.nix этой папки).
  #
  # При миграции на Hyprland этот модуль выключается, а вместо него
  # кладётся рядом power-lock-hyprland.nix (hypridle + hyprlock).
  #
  # Настройки Plasma: питание, блокировка, тачпад.
  #
  # Обработка закрытия крышки полностью передана systemd-logind
  # (см. services.logind в devices/z13/config.nix):
  #   - от батареи → hibernate
  #   - от сети    → lock (kscreenlocker показывает экран блокировки)
  #   - с доком    → ignore
  #
  # PowerDevil от обработки крышки отключён сервисом powerdevil-lid-fix,
  # который записывает LidAction=0 во все профили powerdevilrc и
  # принудительно выставляет TurnOffDisplayIdleTimeoutWhenLockedSec=1,
  # чтобы экран гас после блокировки.
  #
  # PowerDevil продолжает управлять профилями производительности:
  #   KDE PowerDevil → PPD → z13-ppd-sync → z13ctl
  # =====================================================================

  programs.plasma.powerdevil = {
    # --- Профиль при питании от сети (AC) ---
    AC = {
      powerProfile = "balanced";

      # Экран гаснет через 20 минут простоя.
      # idleTimeoutWhenLocked = "immediately" — при блокировке
      # подсветка гаснет сразу.
      turnOffDisplay = {
        idleTimeout = 1200;
        idleTimeoutWhenLocked = "immediately";
      };

      # Автосон отключён.
      # Значение 0 недопустимо (диапазон 60..600000 или null),
      # поэтому idleTimeout = null.
      autoSuspend = {
        action = "nothing";
        idleTimeout = null;
      };
    };

    # --- Профиль при питании от батареи (Battery) ---
    battery = {
      powerProfile = "powerSaving";

      # Экран гаснет через 1 минуту, при блокировке — сразу.
      turnOffDisplay = {
        idleTimeout = 60;
        idleTimeoutWhenLocked = "immediately";
      };

      # Автосон: гибернация через 5 минут простоя.
      # При закрытии крышки logind сам запустит hibernate.
      autoSuspend = {
        action = "hibernate";
        idleTimeout = 300;
      };
    };

    # --- Профиль при низком заряде (LowBattery) ---
    lowBattery = {
      powerProfile = "powerSaving";

      turnOffDisplay = {
        idleTimeout = 60;
        idleTimeoutWhenLocked = "immediately";
      };
    };

    # Не подавлять действие при подключённом внешнем мониторе.
    # По умолчанию true: с внешним монитором закрытие крышки
    # игнорируется. Раскомментировать и поставить false,
    # если хотите, чтобы logind всё равно реагировал на крышку.
    # inhibitLidActionWhenExternalMonitorConnected = false;

    # Пороги батареи.
    batteryLevels = {
      lowLevel = 20;                # Считать батарею низкой при 20%.
      criticalLevel = 5;            # Критический уровень — 5%.
      criticalAction = "hibernate"; # Действие при критическом уровне.
    };
  };

  # =====================================================================
  # Блокировка экрана после пробуждения из гибернации.
  #
  # logind отправляет D-Bus-сигнал Lock при закрытии крышки от сети
  # и перед уходом в гибернацию. KDE (kscreenlocker) ловит его
  # и показывает экран блокировки.
  #
  # LockOnResume=true — KDE также покажет экран блокировки
  # после выхода из гибернации, даже если Lock не пришёл.
  # =====================================================================
  programs.plasma.configFile.kscreenlockerrc.Daemon = {
    Autolock = true;
    LockOnResume = true;
    # Таймаут автоблокировки (5 минут).
    Timeout = 5;
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
      # plasma-manager требует hex-код БЕЗ префикса "0x" — ровно 4 hex-цифры.
      vendorId = "0b05";
      productId = "1a30";
      name = "ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad";

      # Отключать тачпад, пока нажата клавиша на клавиатуре.
      disableWhileTyping = true;

      tapToClick = true;
      naturalScroll = true;
      # Прокрутка двумя пальцами.
      scrollMethod = "twoFinger";
    }
  ];

  # =====================================================================
  # Отключаем обработку крышки в PowerDevil и принудительно
  # выставляем выключение экрана при блокировке.
  #
  # plasma-manager не записывает LidAction и
  # TurnOffDisplayIdleTimeoutWhenLockedSec в powerdevilrc, из-за чего:
  #   1. PowerDevil использует дефолтные значения и конфликтует с logind.
  #   2. Экран не гаснет после блокировки (баг Plasma 6 на Wayland).
  #
  # Этот сервис запускается после PowerDevil и явно ставит:
  #   - LidAction=0 — PowerDevil не трогает крышку.
  #   - TurnOffDisplayIdleTimeoutWhenLockedSec=1 — экран гаснет
  #     через 1 секунду после блокировки. Значение 0 в некоторых
  #     версиях Plasma 6 игнорируется, поэтому 1 — безопасный минимум.
  #
  # Значения LidAction (из исходников PowerDevil):
  #   0 = ничего
  #   1 = выключение
  #   2 = сон
  #   4 = гибернация
  #   8 = блокировка экрана
  # =====================================================================
  systemd.user.services.powerdevil-lid-fix = {
    Unit = {
      Description = "Disable PowerDevil lid handling; force screen off on lock";
      After = [ "graphical-session.target" "plasma-powerdevil.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      # Небольшая задержка, чтобы PowerDevil успел записать свои дефолты.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = pkgs.writeShellScript "powerdevil-lid-fix" ''
        set -euo pipefail
        CONF="$HOME/.config/powerdevilrc"
        KWRITE="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"

        mkdir -p "$(dirname "$CONF")"
        touch "$CONF"

        # LidAction=0 (ничего) для всех профилей.
        # Обработка крышки полностью передана systemd-logind.
        "$KWRITE" --file "$CONF" --group AC         --group SuspendAndShutdown --key LidAction 0
        "$KWRITE" --file "$CONF" --group Battery    --group SuspendAndShutdown --key LidAction 0
        "$KWRITE" --file "$CONF" --group LowBattery --group SuspendAndShutdown --key LidAction 0

        # Выключение экрана через 1 секунду после блокировки.
        # Без этой записи Plasma 6 оставляет экран включённым при
        # блокировке (известный баг), даже если idleTimeoutWhenLocked
        # задан в plasma-manager.
        "$KWRITE" --file "$CONF" --group AC         --group Display --key TurnOffDisplayIdleTimeoutWhenLockedSec 1
        "$KWRITE" --file "$CONF" --group Battery    --group Display --key TurnOffDisplayIdleTimeoutWhenLockedSec 1
        "$KWRITE" --file "$CONF" --group LowBattery --group Display --key TurnOffDisplayIdleTimeoutWhenLockedSec 1

        # Перезапуск PowerDevil, чтобы он перечитал powerdevilrc.
        ${pkgs.systemd}/bin/systemctl --user restart plasma-powerdevil.service || true
      '';
      RemainAfterExit = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

}
