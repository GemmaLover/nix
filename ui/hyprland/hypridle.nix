{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/hyprland/hypridle.nix — аналог связки PowerDevil+kscreenlocker.
  #
  # Порт функциональности KDE (см. devices/z13/home-specific/power-lock.nix):
  #   * простоя → блокировка экрана (Timeout=5 мин в kscreenlockerrc);
  #   * экран гаснет СРАЗУ после блокировки (TurnOffDisplayIdleTimeoutWhenLockedSec=1
  #     + known-bug-фикс Plasma 6) — здесь: afterUnlockKeyboardLocked → dpms off;
  #   * через 20 минут погасший экран уходит в OFF (dpms off_sleep), а
  #     при разблокировке возвращается (dpms on_sleep).
  #
  # ВАЖНО про сон/гибернацию: обработка крышки z13 полностью передана
  # systemd-logind (services.logind.* = ignore в devices/z13/config.nix +
  # lid-демон specific/lid-daemon.nix), поэтому в hypridle таймаутов на
  # suspend/hibernate НЕТ — иначе будет двойное срабатывание, как когда-то
  # с PowerDevil (см. powerdevil-lid-fix). Профили производительности
  # (AC/battery/lowBattery) живут в PPD и z13ctl — DE-независимо.
  # =====================================================================

  services.hypridle = {
    enable = true;

    settings = {
      general = {
        # Перед сном/гибернацией (logind lid-путь) — заблокировать экран:
        # аналог LockOnResume + D-Bus Lock в связке logind+kscreenlocker.
        before_sleep_cmd = "${pkgs.hyprlock}/bin/hyprlock --quiet & sleep 1";
        # После пробуждения — включить дисплеи (dpms мог быть выключен).
        after_sleep_cmd = "${config.programs.hyprland.package}/bin/hyprctl dispatch dpms on";
      };

      listener = [
        # 5 минут бездействия → блокировка (аналог kscreenlockerrc Timeout=5).
        {
          timeout = 300;
          # Запускаем hyprlock как отдельный процесс: `exec` через hyprctl
          # не работает из user-service (нужна переменная окружения сессии),
          # поэтому прямой бинарь + DISPLAY-less Wayland (XDG_RUNTIME_DIR
          # подставляется systemd-user-окружением).
          on-timeout = "${pkgs.hyprlock}/bin/hyprlock --quiet";
          # Разблокировка → снова активен (аналог ActiveChanged=false).
          on-resume = "";
        }
        # Сразу после блокировки (клавиатура hyprlock перехвачена) —
        # погасить экран: аналог TurnOffDisplayIdleTimeoutWhenLockedSec=1,
        # который в KDE приходилось форсировать сервисом powerdevil-lid-fix.
        {
          timeout = 1;
          on-timeout = "${config.programs.hyprland.package}/bin/hyprctl dispatch dpms off";
          on-resume = "${config.programs.hyprland.package}/bin/hyprctl dispatch dpms on";
        }
        # 20 минут общего простоя от сети → гарантированно OFF
        # (аналог AC turnOffDisplay.idleTimeout = 1200 в PowerDevil).
        {
          timeout = 1200;
          on-timeout = "${config.programs.hyprland.package}/bin/hyprctl dispatch dpms off";
          on-resume = "${config.programs.hyprland.package}/bin/hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
