{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ui/hyprland/wlr-protocols.nix — портированные доработки KDE на слой wlroots-протоколов.
  #
  # В Plasma за это отвечали плагины/демоны:
  #   * kwin-plugin «screenshot» (PrintScreen) -> grim + slurp;
  #   * KRunner / Alt+Space                  -> fuzzel (лаунчер);
  #   * Klipper (буфер обмена)               -> cliphist + wl-copy из ui/common/wayland.nix;
  #   * Activity/Task manager                -> htop + btop (уже в base/tools/base.nix).
  #
  # Все эти бинари нужны СИСТЕМЕ (доступны всем пользователям и ранним
  # скриптам), а не только lexi — поэтому они здесь, а не в HM.
  # =====================================================================
in
{
  environment.systemPackages = with pkgs; [
    grim        # скриншоты Wayland (аналог Spectacle: `grim -g "$(slurp)" out.png`)
    slurp       # выделение области для grim (интерактивный crop)
    cliphist    # менеджер истории буфера обмена (заменяет Klipper)
    wtype       # симуляция ввода для скриптов (KDE не требовал — Wayland-специфика)
    hyprpicker  # пипетка цвета (аналог Color Picker в Plasma)
  ];

  # Глобальные переменные окружения для сессий:
  #   * XDG_CURRENT_DESKTOP — нужен portal'ам и Electron-приложениям,
  #     чтобы корректно определять Hyprland (в KDE ставился автоматически);
  #   * GDK_BACKEND / QT_QPA_PLATFORM — явный Wayland для GTK/Qt, иначе
  #     Qt-приложения могут упасть в XWayland без DE-сессии.
  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    GDK_BACKEND = "wayland";
    QT_QPA_PLATFORM = "wayland";
  };
}
