{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/niri/niri.nix — системный слой Niri.
  #
  # Включает Niri как композитор, настраивает графический вход через
  # Noctalia Greeter (greetd + noctalia-greeter-session), добавляет
  # Xwayland-сателлит, polkit/keyring и PAM-разблокировку GNOME Keyring.
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
  # Noctalia Greeter — графический экран входа (вместо tuigreet).
  #
  # Модуль noctalia-greeter.nixosModules.default (подключён в mkSystem)
  # сам:
  #   * включает greetd;
  #   * включает accounts-daemon (аватарки пользователей);
  #   * включает polkit;
  #   * выставляет greetd.default_session.command = noctalia-greeter-session.
  #
  # Поэтому отдельный блок services.greetd с tuigreet УДАЛЁН.
  # Если оставить его рядом — будет конфликт за greetd.settings.
  #
  # Настройки:
  #   session.default = "niri" — сессия по умолчанию (имя из desktop-entry
  #     /run/current-system/sw/share/wayland-sessions/niri.desktop).
  #     Если после ребута greeter не находит сессию, проверьте точное
  #     Name= в этом файле (может быть "Niri" с большой буквы).
  #   user.default = "lexi" — сразу открывает ввод пароля для lexi.
  #   appearance.theme_mode = "dark" — тёмная тема (синхронизируется с Noctalia).
  #   cursor.theme = "Adwaita" — курсор как в Niri (home.sessionVariables).
  #   cursor.size = 24 — тот же размер, что XCURSOR_SIZE в home.nix.
  #
  # Документация:
  #   https://docs.noctalia.dev/greeter/installation/#nixos-declarative-setup
  #   https://docs.noctalia.dev/greeter/configuration/
  # =====================================================================
  services.displayManager.noctalia-greeter = {
    enable = true;

    settings = {
      # Сессия по умолчанию.
      session.default = "niri";

      # Пользователь по умолчанию — сразу экран ввода пароля.
      user.default = "lexi";

      # Тёмная тема (синхронизируется с Noctalia Shell при включённом Sync).
      appearance.theme_mode = "dark";

      # Курсор: тот же, что в Niri (XCURSOR_THEME / XCURSOR_SIZE).
      cursor = {
        theme = "Adwaita";
        size = 24;
      };

      # Раскладка клавиатуры на экране входа — та же, что в системе
      # (base/system/keyboard.nix: us,ru с grp:caps_toggle).
      keyboard.layout = "us,ru";
      keyboard.options = "grp:caps_toggle,caps:escape";
    };
  };

  # =====================================================================
  # PAM-разблокировка GNOME Keyring при входе через greetd.
  #
  # Без этого gnome-keyring-daemon запускается, но остаётся заблокированным
  # (не получает пароль от PAM), и git-credential-libsecret не может
  # сохранить или прочитать пароль. При логине через greetd пароль
  # передаётся в PAM-модуль pam_gnome_keyring, который разблокирует
  # keyring автоматически — без второго запроса пароля.
  #
  # Это стандартный и рекомендуемый способ для Niri/Sway/Hyprland
  # на NixOS (см. wiki.nixos.org «Secret Service»).
  #
  # ВАЖНО: Noctalia Greeter использует тот же greetd, поэтому строка
  # security.pam.services.greetd.enableGnomeKeyring остаётся без изменений.
  # =====================================================================
  security.pam.services.greetd.enableGnomeKeyring = true;

  # =====================================================================
  # Xwayland-сателлит — для X11-приложений (AIMP и т.п.).
  # =====================================================================
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    # Курсор Adwaita для экрана входа: greeter работает в системном
    # контексте (не в HM), поэтому пакет должен быть в systemPackages,
    # иначе cursor.theme = "Adwaita" не найдётся.
    adwaita-icon-theme
  ];

  # =====================================================================
  # Polkit и Secret Service.
  #
  # security.polkit.enable — для pkexec и GUI-запросов привилегий.
  # services.gnome.gnome-keyring.enable — поднимает gnome-keyring-daemon
  # как провайдер org.freedesktop.secrets (Secret Service).
  #
  # ВАЖНО: noctalia-greeter.nixosModules.default тоже включает polkit,
  # но дублирование идемпотентно и не вредит. Оставляем для явности.
  # =====================================================================
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # =====================================================================
  # XDG-портал.
  # =====================================================================
  xdg.portal = {
  enable = true;

  # Бэкенды порталов. gtk — универсальный и самый надёжный в Niri.
  extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
  ];

  # Явно указываем Niri, какой бэкенд использовать для FileChooser.
  # Без этой строки портал может выбрать неподходящий бэкенд
  # (например, gnome или kde), если они случайно установлены.
  config.niri = {
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    "org.freedesktop.impl.portal.OpenURI"     = [ "gtk" ];
  };
};
}
