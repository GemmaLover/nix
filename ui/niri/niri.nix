{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/niri/niri.nix — системный слой Niri.
  #
  # Включает Niri как композитор, настраивает greetd для запуска
  # niri-session, добавляет Xwayland-сателлит, polkit/keyring и
  # PAM-разблокировку GNOME Keyring при входе.
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
  # (0.3.x) и не ломает eval.
  programs.niri.package = pkgs.niri;

  # =====================================================================
  # greetd — вход в сессию Niri.
  #
  # niri-session — wrapper из niri-flake, который корректно выставляет
  # окружение и запускает Niri. tuigreet — минималистичный TUI-логин.
  #
  # ВАЖНО: атрибут tuigreet в актуальном nixpkgs вынесен на верхний
  # уровень (pkgs.tuigreet), вложенный pkgs.greetd.tuigreet удалён.
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
  # === НОВОЕ: PAM-разблокировка GNOME Keyring при входе через greetd ===
  #
  # Без этого gnome-keyring-daemon запускается, но остаётся заблокированным
  # (не получает пароль от PAM), и git-credential-libsecret не может
  # сохранить или прочитать пароль. При логине через greetd пароль
  # передаётся в PAM-модуль pam_gnome_keyring, который разблокирует
  # keyring автоматически — без второго запроса пароля.
  #
  # Это стандартный и рекомендуемый способ для Niri/Sway/Hyprland
  # на NixOS (см. wiki.nixos.org «Secret Service»).
  # =====================================================================
  security.pam.services.greetd.enableGnomeKeyring = true;

  # =====================================================================
  # Xwayland-сателлит — для X11-приложений (AIMP и т.п.).
  # =====================================================================
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];

  # =====================================================================
  # Polkit и Secret Service.
  #
  # security.polkit.enable — для pkexec и GUI-запросов привилегий.
  # services.gnome.gnome-keyring.enable — поднимает gnome-keyring-daemon
  # как провайдер org.freedesktop.secrets (Secret Service).
  # =====================================================================
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # =====================================================================
  # XDG-портал.
  # =====================================================================
  xdg.portal.enable = true;
}
