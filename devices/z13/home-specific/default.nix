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
      ./plasma-launchers-fix.nix # activation-хук ярлыков KDE (вынесен из home.nix)
    ]
    ++ lib.optionals (cfg.ui == "hyprland") [
      # Миграция выполнена: DE-специфичные модули Hyprland лежат рядом.
      ../../../ui/hyprland/home.nix # композитор, hyprlock, аналоги KDE-утилит
      ./power-lock-hyprland.nix   # hypridle/hyprlock (аналог power-lock.nix)
      ./asus-backlight-hyprland.nix # подсветка по IPC hyprlock (аналог kde-версии)
      # caffeine на Hyprland НЕ нужен: ингибирование сна делает сам
      # hyprland (windowrule v1/v2 -> inhibit_idle), см. ui/hyprland/home.nix.
    ];
}
