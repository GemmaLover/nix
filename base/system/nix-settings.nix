{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;

    # === НОВОЕ: игнорировать nixConfig из flake-файлов ===
    # Запрещает Nix автоматически применять настройки кэшей из flake-файлов,
    # что предотвращает зависания на недоступных niri.cachix.org и подобных.
    accept-flake-config = false;

    # Явно задаем только надежные кэши.
    substituters = [ "https://cache.nixos.org/" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

    # Таймаут и fallback на случай проблем с сетью.
    connect-timeout = 5;
    fallback = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
