# flake.nix
{
  description = "NixOS multi-device configuration for z13, PC, and ASUS laptop";

  inputs = {
    # Актуальный стабильный релиз NixOS 26.05 «Yarara».
    # Обновления безопасности до 2026-12-31.
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";

    # Home Manager — декларативное управление пользовательскими конфигами.
    # Версия release-26.05 соответствует nixpkgs 26.05.
    home-manager = {
      # url = "github:nix-community/home-manager/release-26.05";
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disko — декларативная разметка дисков с LUKS.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # plasma-manager — декларативное управление настройками KDE Plasma.
    # Нужен для настройки PowerDevil (авто-переключение профилей
    # при смене питания), темы, раскладки и т.д.
    # У проекта нет веток release-XX.XX — используется trunk (Plasma 6).
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Ядра CachyOS (LTO, BORE, LTS и т.д.) с собственным бинарным кэшем.
    # nix-cachyos-kernel = {
    #   url = "github:xddxdd/nix-cachyos-kernel/release";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # CachyOS-ядра с патчами (BORE, LTO, zen4-оптимизация) и бинарным кэшем.
    # release-ветка — стабильные ядра, синхронизированные с nixpkgs.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    # ВАЖНО: НЕ ставим inputs.nixpkgs.follows = "nixpkgs" — иначе версия
    # ядра будет зависеть от вашего nixpkgs и может «уплыть» с 7.2.8
    # на что-то другое. pinned-оверлей использует nixpkgs самого flake.

    # === НОВОЕ: Niri — Wayland-композитор ===
    # sodiboo/niri-flake предоставляет Nix-нативную конфигурацию (programs.niri.settings)
    # и официальный NixOS-модуль. Это не «прослойка», а рекомендованный сообществом
    # источник пакета niri и модулей для NixOS/Home Manager.
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === НОВОЕ: Noctalia — Wayland-шелл (панель, лаунчер, уведомления) ===
    # Официальный репозиторий Noctalia.
    # ВАЖНО: если вы хотите использовать бинарный кэш Cachix от Noctalia,
    # НЕ добавляйте inputs.nixpkgs.follows = "nixpkgs" — иначе будут кэш-промахи.
    # Если готовы собирать локально — можно раскомментировать строку follows.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      # inputs.nixpkgs.follows = "nixpkgs"; # раскомментируйте, если не нужен кэш
    };

    # === НОВОЕ: Noctalia Greeter — графический экран входа ===
    # Официальный greeter для greetd, визуально синхронизируется с Noctalia Shell.
    # Модуль inputs.noctalia-greeter.nixosModules.default сам:
    #   * включает greetd;
    #   * включает accounts-daemon (для аватарок пользователей);
    #   * выставляет default_session.command на noctalia-greeter-session.
    # Поэтому старый блок services.greetd с tuigreet нужно будет УДАЛИТЬ
    # из ui/niri/niri.nix, иначе будет конфликт.
    #
    # Ссылки:
    #   https://docs.noctalia.dev/greeter/ (Installation)
    #   https://docs.noctalia.dev/greeter/configuration/ (ключи greeter.toml)
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      # follows не ставим — как и для noctalia, чтобы не ломать кэш.
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, plasma-manager, nix-cachyos-kernel, niri, noctalia, noctalia-greeter, ... }@inputs:
    let
      # Фабрика нод nixosConfigurations (см. lib/mkSystem.nix):
      # подставляет disko, home-manager, plasma-manager, опции kda.opts
      # и диспетчеры осей ui/ и profiles/ — устройство объявляет только
      # свои оси в devices/<name>/config.nix.
      # === ИЗМЕНЕНО: передаём niri, noctalia и noctalia-greeter в mkSystem ===
      mkSystem = import ./lib/mkSystem.nix {
        inherit inputs nixpkgs home-manager disko plasma-manager niri noctalia noctalia-greeter;
      };
    in
    {
      nixosConfigurations = {
        # === Устройство: ASUS Z13 ===
        z13 = mkSystem "z13" {
          deviceModule = ./devices/z13/config.nix;
          # Home-модули пользователя lexi
          # (пустой список => HM не подключается).
          userHome = user: [
            ./devices/z13/home.nix
          ];
        };

        # === Устройство: PC (AMD CPU + NVIDIA GPU) ===
        # ...
      };
    };
}
