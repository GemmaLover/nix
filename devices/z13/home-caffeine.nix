{ config, pkgs, ... }:

{
  # === Caffeine-ng ===
  # Автоматически блокирует засыпание и блокировку экрана,
  # когда приложение (Firefox, VLC и т.д.) запрашивает ингибирование.
  # Работает через D-Bus и MPRIS, поддерживает Wayland.
  services.caffeine = {
    enable = true;
    # Пакет caffeine-ng из nixpkgs.
    package = pkgs.caffeine-ng;
  };
}
