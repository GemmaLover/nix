{ config, lib, pkgs, kdaOpts ? { ui = "none"; profiles = [ ]; }, ... }:

let
  # =====================================================================
  # devices/z13/home-specific/ — пользовательский слой z13.
  #
  # Файлы здесь зависят ОТ ЖЕЛЕЗА и (иногда) ОТ ОБОЛОЧКИ. Диспетчер
  # подключает DE-специфичные модули по оси ui (kdaOpts пробрасывается
  # из NixOS-конфига через home-manager.extraSpecialArgs в mkSystem),
  # чтобы при смене Plasma -> Hyprland достаточно было положить рядом
  # *-hyprland.nix.
  # =====================================================================
  cfg = kdaOpts;
in
{
  imports = [ ]
    ++ lib.optionals (cfg.ui == "kde") [
      ./power-lock.nix           # PowerDevil / kscreenlocker / plasma-manager
      ./caffeine-kde.nix         # трей caffeine-ng (programs.caffeine-ng)
      ./asus-backlight-kde.nix   # гашение подсветки по сигналу kscreenlocker
    ]
    ++ lib.optionals (cfg.ui == "hyprland") [
      # TODO(миграция): ./power-lock-hyprland.nix (hypridle/hyprlock)
      # TODO(миграция): ./caffeine-hyprland.nix (inhibit через hypridle)
      # TODO(миграция): ./asus-backlight-hyprland.nix (сокет hyprlock)
    ];
}
