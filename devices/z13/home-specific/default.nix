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
      ./caffeine-kde.nix         # трей caffeine-ng (home.packages + xdg.autostart)
      ./asus-backlight-kde.nix   # гашение подсветки по сигналу kscreenlocker
    ]
    # Hyprland: портированные аналоги KDE-доработок (карта — в guide.md).
    # Каждый *-hyprland.nix — прямой наследник своего KDE-файла.
    ++ lib.optionals (cfg.ui == "hyprland") [
      ./power-lock-hyprland.nix        # hypridle/hyprlock + waybar + тачпад (порт power-lock.nix)
      ./caffeine-hyprland.nix          # caffeine-ng через portal Inhibit (порт caffeine-kde.nix)
      ./asus-backlight-hyprland.nix    # подсветка по сокету hyprlock IPC (порт asus-backlight-kde.nix)
      ./cliphist-hyprland.nix          # история буфера вместо Klipper
    ];
}
