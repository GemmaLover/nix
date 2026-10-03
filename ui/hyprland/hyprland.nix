{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ui/hyprland/hyprland.nix — системный слой Hyprland.
  #
  # Миграция с KDE (порт всех доработок; карта — в guide.md):
  #   SDDM            -> greetd + tuigreet (ниже)
  #   PowerDevil      -> power-profiles-daemon (уже в devices/z13/specific/performance.nix, DE-независимо)
  #   kscreenlocker   -> hyprlock (./hyprlock.nix) + hypridle (./hypridle.nix)
  #   plasma-manager  -> programs.hyprland в Home Manager (devices/z13/home-specific/hyprland/)
  #   bluedevil       -> blueman (ниже)
  #   Dolphin/Konsole -> thunar / foot (базовый софт остаётся из base/tools/base.nix)
  #   caffeine-ng     -> тот же бинарь + XDG autostart (home-слой, DE-независимо)
  # =====================================================================

  # Минимальный рабочий hyprland.conf: пишется в /etc/hyprland/hyprland.conf,
  # пользовательский ~/.config/hypr/hyprland.conf (Home Manager) приоритетнее.
  # Здесь — только то, без чего сессия не запустится/не будет безопасна.
  systemHyprlandConf = ''
    # === Системный дефолт Hyprland (переопределяется ~/.config/hypr/hyprland.conf) ===

    # Блокировка экрана по SUPER+L (аналог Meta+L в KDE).
    bind = SUPER, L, exec, hyprlock

    # Базовые клавиши для отладки (основные бинды задаёт HM-конфиг z13).
    bind = SUPER, Q, killactive,
    bind = SUPER SHIFT, E, exit,
  '';
in
{
  programs.hyprland = {
    enable = true;
    # EGL/XCB-обёртки: запуск X11-приложений (brave пока требует X11-фичи,
    # игры через Steam/Proton — тоже XWayland).
    xwayland.enable = true;
  };

  # Конфиг «из коробки», чтобы система была рабочей даже без HM-конфига.
  environment.etc."hyprland/hyprland.conf".text = systemHyprlandConf;

  # Менеджер входа: greetd вместо SDDM (SDDM тянет Qt/KDE-зависимости).
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --remember --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # Гипернатива bluedevil для Wayland-стека без KDE.
  # NetworkManager-аппарет (tray) даёт waybar (см. home-слой).
  environment.systemPackages = with pkgs; [
    xdg-desktop-portal-hyprland   # скриншоты, пикер файлов, screen-cast
    blueman                       # Bluetooth-трей/manager (аналог bluedevil)
    networkmanagerapplet          # Wi-Fi tray (для waybar/трея)
    fuzzel                        # лаунчер (аналог KRunner: Super+Space ниже в HM)
    foot                          # терминал (аналог Konsole)
    waypaper                      # обои (аналог plasma wallpaper plugin)
    hyprpolkitagent               # polkit-агент для запроса пароля админа
  ];

  # hypridle/hyprlock/wlr-protocols подключаются через ./default.nix
  # (раньше были здесь же — дублирование убрано).

  # SDDM остаётся включённым при ui = "kde" (ui/kde/plasma.nix); при переходе
  # на Hyprland его надо явно выключить, иначе два login-manager'а конфликтуют
  # за getty/tty и автовход.
  services.displayManager.sddm.enable = lib.mkForce false;

  # Wayland-сессии нужен dbus-session per user — уже есть в базовом образе,
  # но явно фиксируем для окружения пользователя lexi.
  services.dbus.enable = true;
}
