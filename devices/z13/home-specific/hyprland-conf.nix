{ config, lib, pkgs, ... }:

# =====================================================================
# devices/z13/home-specific/hyprland-conf.nix — конфиг Hyprland
# (~/.config/hypr/hyprland.conf) через xdg.configFile.
#
# Почему не programs.hyprland в Home Manager: HM-опция programs.hyprland
# существует только при включённом NixOS-модуле programs.hyprland.enable
# (он добавляет её через home-manager.sharedModules), а у нас системный
# слой ui/hyprland/hyprland.nix намеренно его ВЫКЛЮЧАЕТ, чтобы не тянуть
# сессионную обвязку Plasma-эпохи и управлять greetd. Поэтому конфиг
# пишем напрямую — это DE-agnostic по механике и портируемо на другие
# машины (у другого железа отличается только блок input).
#
# Содержимое — порт доработок KDE-слоя:
#   plasma-manager input.touchpads (GZ302EA ASUS 0b05:1a30 из
#     devices/z13/specific/asus-input.nix + base-дефолты ui/common/input.nix)
#     -> блок input:touchpad ниже;
#   глобальные хоткеи KDE (Konsole/KRunner/Spectacle/Klipper)
#     -> bind: foot/fuzzel/grim+slurp/cliphist;
#   закрытие крышки -> bindl Lid Switch (дубль logind-пути lid-демона).
# =====================================================================

{
  xdg.configFile."hypr/hyprland.conf".text = ''
    # === Ввод (порт plasma-manager input.touchpads для GZ302EA) ===
    input {
      kb_layout = us,ru            # раскладка была в Plasma-профиле; сохраняем
      follow_mouse = 1

      touchpad {
        # disableWhileTyping — по умолчанию ON в libinput; фиксируем явно.
        disable_while_typing = true
        # tapToClick=true
        tap_to_click = true
        # naturalScroll=true
        natural_scroll = true
        # scrollMethod="twoFinger"
        scroll_method = two_finger
      }
    }

    # === Прочее базовое (минимальная рабочая сессия) ===
    general {
      gaps_in = 5
      gaps_out = 10
      border_size = 2
      layout = dwindle
    }

    decoration {
      rounding_power = 2
    }

    # === Клавиши (аналоги KDE-глобалок) ===
    bind = SUPER, RETURN, exec, foot                          # Konsole -> foot
    bind = SUPER, SPACE, exec, fuzzel                         # KRunner -> fuzzel
    bind = CTRL ALT, L, exec, hyprlock                        # ручной лок (KScreensaver)
    bind = SUPER SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy  # Spectacle region -> clipboard
    bind = , Print, exec, grim $HOME/Pictures/screenshot-$(date +%F-%H%M%S).png  # PrintScreen (Spectacle)
    # История буфера (Klipper): fuzzel-меню cliphist + вставка через wl-copy.
    bind = SUPER, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy

    # Закрытие крышки: локальный дубль logind-пути (lid-daemon дергает
    # loginctl lock-sessions; этот бинд реагирует на событие Hyprland).
    bindl = , switch:on:Lid Switch, exec, hyprlock

    # === Автозапуск сессии ===
    # waybar (панель вместо плазм Plasma), hypridle (таймауты блокировки —
    # конфиг генерирует Home Manager services.hypridle в
    # ./power-lock-hyprland.nix -> тот же ~/.config/hypr/hypridle.conf).
    exec-once = waybar
    exec-once = hypridle
  '';

  # Пакеты, вызываемые из конфига (foot/fuzzel/grim/slurp/wl-clipboard/
  # cliphist/waybar ставит ./power-lock-hyprland.nix — здесь только сам
  # композитор, чтобы hyprlock/hypridle/hyprctl были в PATH сессии).
  home.packages = [ pkgs.hyprland ];
}
