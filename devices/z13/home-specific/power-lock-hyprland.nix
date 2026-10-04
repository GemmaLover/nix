{ config, pkgs, ... }:

let
  # =====================================================================
  # devices/z13/home-specific/power-lock-hyprland.nix — Home Manager-слой
  # питания/блокировки/ввода для Hyprland на z13. Портированный аналог
  # power-lock.nix (KDE): подключается диспетчером home-specific/default.nix
  # только при kda.opts.ui = "hyprland".
  #
  # Соответствия перенесённых компонентов:
  #   programs.plasma.powerdevil      -> services.hypridle.settings (таймауты)
  #   kscreenlockerrc (Autolock/…)    -> programs.hyprlock + hypridle lock
  #   programs.plasma.input.touchpads -> programs.hyprland.input (libinput)
  #   powerdevil-lid-fix              -> не нужен: крышку обрабатывает
  #                                       udev/lid-daemon (specific/), а
  #                                       гашение экрана делает hypridle.
  #
  # Обработка закрытия крышки полностью передана systemd-logind
  # (см. services.logind в devices/z13/config.nix):
  #   - от батареи → suspend (сон). Гибернация ОТКАЗАНА: ломала систему.
  #   - от сети    → lock (hyprlock показывает экран блокировки)
  #   - с доком    → ignore
  #
  # PowerDevil от обработки крышки отключён сервисом powerdevil-lid-fix,
  # который записывает LidAction=0 во все профили powerdevilrc и
  # принудительно выставляет TurnOffDisplayIdleTimeoutWhenLockedSec=1,
  # чтобы экран гас после блокировки.
  # ^ (наследие KDE; на Hyprland эти функции берут onLock/offSleep ниже.)
  #
  # PowerDevil продолжает управлять профилями производительности:
  #   KDE PowerDevil → PPD → z13-ppd-sync → z13ctl
  # ^ на Hyprland цепочка та же, но виджет PPD — в waybar (см. ниже).
  # =====================================================================

  # Единые команды блокировки/гашения подсветки (используются hypridle):
  # вызывают oneshot-сервисы kbd-backlight-off/on ниже.
  lockCmd     = "${pkgs.systemd}/bin/systemctl --user start kbd-backlight-off.service";
  unlockCmd   = "${pkgs.systemd}/bin/systemctl --user start kbd-backlight-on.service";
  screenOff   = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
  screenOn    = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
in
{
  # --- hypridle: аналог таймаутов PowerDevil + автоблокировки kscreenlocker ---
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        # Не засыпать от бездействия целиком — сон только по явной команде
        # или закрытию крышки (как autoSuspend.action="nothing" в AC-профиле).
        after_sleep_cmd = screenOn;
        # Перед сном: блокировка через штатный механизм logind/hyprlock.
        before_sleep_cmd = "loginctl lock-session || true";
        lock_cmd = "pidof hyprlock || ${pkgs.hyprlock}/bin/hyprlock";
      };

      # --- Аналог TurnOffDisplayIdleTimeoutWhenLockedSec из PowerDevil ---
      # Гашение экрана сразу после блокировки делает listener ниже:
      # on-timeout ставит локер И гасит DPMS; on-resume включает экран
      # и подсветку (kbd-backlight-on).

      listener = [
        # Автосон отключён (baseline: idleTimeout=null в AC).
        # Значение 0 недопустимо (диапазон 60..600000 или null),
        # поэтому здесь просто нет listener'а «suspend by timeout».

        # Экран гаснет через 20 минут простоя (AC: turnOffDisplay.idleTimeout=1200).
        # На батарее стратегия та же: гасим DPMS, дальше крышка/logind.
        {
          timeout = 1200;
          on-timeout = screenOff;
          on-resume = screenOn;
        }

        # Автоблокировка через 5 минут (kscreenlockerrc Timeout=5) +
        # гашение сразу после локка (TurnOffDisplayIdleTimeoutWhenLockedSec=1):
        # on-timeout ставит локер и гасит DPMS, on-resume — включает экран
        # и подсветку.
        {
          timeout = 300;
          on-timeout = "${lockCmd} && ${screenOff}";
          on-resume = "${unlockCmd} && ${screenOn}";
        }
      ];
    };
  };

  # --- hyprlock: аналог kscreenlocker ---
  # programs.hyprlock.enable и конфиг (settings) подключаются по оси ui
  # в домашнем слое ui-модуля (см. ui/hyprland/home.nix); здесь только
  # immediateExecution: локер стартует сразу при входе в сессию и
  # блокирует экран после resume (аналог LockOnResume=true из
  # kscreenlockerrc).
  programs.hyprlock.immediateExecution = true;

  # Гашение подсветки клавиатуры при блокировке (см. asus-backlight-hyprland.nix):
  # hypridle дёргает эти oneshot-сервисы вместо D-Bus-сигнала kscreenlocker.
  systemd.user.services.kbd-backlight-off = {
    Unit.Description = "Keyboard backlight off (invoked by hypridle lock)";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.asusctl}/bin/asusctl -k off";
    };
  };
  systemd.user.services.kbd-backlight-on = {
    Unit.Description = "Keyboard backlight low (invoked by hypridle resume)";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.asusctl}/bin/asusctl -k low";
    };
  };

  # =====================================================================
  # Настройки ввода (тачпад) — порт programs.plasma.input.touchpads.
  #
  # KDE на Wayland игнорирует services.libinput.touchpad.disableWhileTyping,
  # потому что управляет настройками ввода сам. plasma-manager пишет
  # нужные значения в ~/.config/kcminputrc — оттуда KDE их читает.
  # ^ На Hyprland то же самое делает `programs.hyprland.input` — он пишет
  # libinput-настройки прямо в hyprland.conf ([input] section).
  #
  # vendorId и productId — обязательные поля. По ним KDE идентифицирует
  # конкретное устройство. Без них plasma-manager падает с ошибкой
  # "vendorId is not of type string".
  # ^ В Hyprland селектор устройства — по имени (match).
  #
  # Значения взяты из `udevadm info` для GZ302EA-Keyboard Touchpad:
  #   ID_VENDOR_ID=0b05  (ASUSTeK)
  #   ID_MODEL_ID=1a30   (GZ302EA-Keyboard)
  # =====================================================================
  wayland.windowManager.hyprland.settings.input = [{
    # match по имени устройства (аналог пары vendor/product из Plasma).
    "device:name" = "ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad";

    # Отключать тачпад, пока нажата клавиша на клавиатуре.
    "touchpad:disable_while_typing" = true;

    "touchpad:tap-to-click" = true;
    "touchpad:natural_scroll" = true;
    # Прокрутка двумя пальцами.
    "touchpad:scroll_factor" = 1.0;
  }];

  # =====================================================================
  # Пороги батареи (batteryLevels из PowerDevil: low=20, critical=5,
  # criticalAction=suspend — отказ от hibernate: гибернация ломала
  # систему) — на Hyprland их берёт на себя upower +
  # нотификации mako; критическое действие (suspend при 5%) задаётся
  # через udev-правило UPower или вручную в сценарии battery-watch:
  # TODO(дальнейшая миграция): сервис battery-watch при <5% -> suspend.
  # Пока поведение совпадает с logind-политикой закрытия крышки.
  # =====================================================================

  # =====================================================================
  # Профили производительности: виджет PPD из плазма-трея заменён
  # модулем waybar (custom/power-profiles вызывает powerprofilesctl).
  # Сервис z13-ppd-sync (devices/z13/specific/performance.nix) слушает
  # тот же D-Bus PPD — менять его под Hyprland не нужно.
  # =====================================================================
  programs.waybar = {
    enable = true;
    settings = [{
      layer = "top";
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [
        "custom/power-profiles"
        "network"
        "bluetooth"
        "battery"
        "pulseaudio"
        "tray"
        "clock"
      ];

      # Аналог виджета батарейки KDE со списком профилей PPD.
      "custom/power-profiles" = {
        exec = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl get";
        interval = 5;
        tooltip = false;
        format = "⚡ {}";
        on-click = "${pkgs.wofi}/bin/wofi --dmenu 'power-saver|balanced|performance' | xargs -r ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set";
      };

      battery = {
        # Пороги как в PowerDevil: lowLevel=20, criticalLevel=5.
        states = {
          warning = 20;
          critical = 5;
        };
        format = "{capacity}% {icon}";
        icon = "";
      };
    }];
    style = ''
      * { font-family: "JetBrainsMono Nerd Font", monospace; font-size: 13px; }
      window#waybar { background: rgba(26,27,34,0.9); color: #cdd6f4; }
      #battery.warning { color: #f9e2af; }
      #battery.critical { color: #f38ba8; }
    '';
  };
}
