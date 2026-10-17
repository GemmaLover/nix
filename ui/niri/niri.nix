{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/niri/niri.nix — системный слой Niri.
  #
  # Включает Niri как композитор (niri.nixosModules.niri уже подключён
  # в lib/mkSystem.nix — здесь только программный флаг), настраивает
  # greetd для запуска niri-session, добавляет Xwayland-сателлит для
  # X11-приложений (AIMP и др.) и включает polkit/keyring.
  #
  # Пользовательские настройки Niri (биндинги, layout, spawn-at-startup)
  # живут в ui/niri/home.nix — HM-слое этой оси.
  # =====================================================================

  # Niri как системный композитор.
  programs.niri.enable = true;

  # === ВАЖНО: пакет Niri берём из nixpkgs, а не из niri-flake ===
  # Пакет niri-stable из niri-flake на текущем коммите всё ещё ссылается
  # на libdisplay-info_0_2, который удалён из nixpkgs (nixos-unstable).
  # NixOS-пакет pkgs.niri уже собран с актуальной libdisplay-info
  # (0.3.x) и не ломает eval. niri-flake официально допускает такую
  # замену: «you could set programs.niri.package = pkgs.niri;».
  #
  # Если позже понадобится самая свежая версия Niri с фичами, которых
  # ещё нет в nixpkgs, можно вернуться на niri-unstable, но только
  # после того, как upstream обновит зависимость от libdisplay-info.
  programs.niri.package = pkgs.niri;

  # =====================================================================
  # greetd — вход в сессию Niri.
  #
  # niri-session — wrapper из niri-flake, который корректно выставляет
  # окружение (XDG_RUNTIME_DIR, WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS)
  # и запускает Niri. Прямой запуск `niri` из greetd работает хуже.
  #
  # tuigreet — минималистичный TUI-логин. --remember + --remember-session
  # позволяют greetd запоминать последнего пользователя и сессию.
  #
  # ВАЖНО: атрибут tuigreet в актуальном nixpkgs вынесен на верхний
  # уровень (pkgs.tuigreet), вложенный pkgs.greetd.tuigreet удалён —
  # при его использовании nix flake check падает с «attribute 'tuigreet'
  # missing». Проверено по конфигурациям сообщества: используется
  # именно pkgs.tuigreet.
  # =====================================================================
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # =====================================================================
  # Xwayland-сателлит — для X11-приложений (AIMP и т.п.).
  #
  # Niri автоматически запускает xwayland-satellite, если бинарник есть
  # в $PATH при первом подключении X11-клиента. Версия >= 0.7 работает
  # из коробки.
  # =====================================================================
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];

  # =====================================================================
  # Polkit и Secret Service.
  #
  # KDE Plasma 6 включал их автоматически через plasma6-модуль. После
  # перехода на Niri их нужно включить явно, иначе:
  #   * pkexec и GUI-запросы привилегий (монтирование USB, установка
  #     пакетов из магазина) не работают;
  #   * браузеры не могут сохранять пароли (нет secret-service).
  # =====================================================================
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # =====================================================================
  # XDG-портал.
  #
  # ui/common/wayland.nix уже кладёт xdg-desktop-portal-gtk в
  # systemPackages, но не включает сам portal-сервис. Включаем его
  # здесь — иначе скриншоты, выбор файлов в Flatpak-приложениях и
  # screen sharing не работают.
  # =====================================================================
  xdg.portal.enable = true;
}
