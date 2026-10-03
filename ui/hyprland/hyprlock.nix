{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/hyprland/hyprlock.nix — экран блокировки Hyprland (аналог kscreenlocker).
  #
  # Портирует поведение KDE из devices/z13/home-specific/power-lock.nix:
  #   * Autolock=true          -> hypridle слушает таймаут и запускает hyprlock;
  #   * Timeout=5              -> тот же таймаут в hypridle (300 с);
  #   * LockOnResume=true      -> logind шлёт PrepareForSleep/сигнал Lock при
  #     закрытии крышки от сети и перед гибернацией; before_sleep_cmd hypridle
  #     (см. ./hypridle.nix) запускает hyprlock — экран заблокирован и после
  #     пробуждения, как в связке logind+kscreenlocker на Plasma.
  #
  # programs.hyprlock.settings пишет общесистемный конфиг
  # /etc/hypr/hyprlock.conf (дефолт для всех пользователей). Пользовательский
  # overrides (~/.config/hypr/hyprlock.conf) не создаём — базовый вид
  # (blur + поле пароля + часы) полностью заменяет kscreenlocker-Greeter.
  # =====================================================================

  programs.hyprlock = {
    enable = true;
    settings = {
      # Общее: blur фона, показ часов (аналог plasma-faces/kscreenlocker UI).
      general = {
        disable_greeter = false;
      };

      # Затемнение + input-field: минимальный рабочий локер.
      background = {
        color = "rgba(20,20,30,0.95)";
        blur = true;
      };

      # input-field — список блоков в hyprlock.conf; HM-модуль принимает list.
      input-field = [ {
        size = "250, 50";
        outline_thickness = 2;
        dots_size = 0.2;
        dots_spacing = 0.2;
        outer_color = "rgb(60,60,80)";
        inner_color = "rgb(30,30,45)";
        font_color = "rgb(220,220,230)";
        fade_on_empty = false;
        placeholder_text = ''<i>Password...</i>'';
        hide_input = false;
        position = "0, -25";
        halign = "center";
        valign = "center";
      } ];

      # Часы над полем ввода (аналог виджета времени на lock-экране Plasma).
      label = [ {
        text = "cmd[update:3600000] date +'%H:%M'";
        color = "rgba(230,230,240,0.95)";
        font_size = 72;
        font_family = "Noto Sans";
        position = "0, 120";
        halign = "center";
        valign = "center";
      } ];
    };
  };
}
