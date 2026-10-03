{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/home-specific/power-lock-hyprland.nix — домашний слой
  # питания/блокировки/тачпада для Hyprland.
  #
  # Портирует функциональность power-lock.nix (KDE/plasma-manager) один-в-один:
  #
  #   PowerDevil AC/battery turnOffDisplay + autoSuspend
  #     -> hypridle (таймауты блокировки и гашения экрана; сон/гибернацию
  #        обрабатывает logind + lid-демон — см. ui/hyprland/hypridle.nix,
  #        таймаутов suspend здесь НЕТ намеренно);
  #   kscreenlockerrc Autolock/LockOnResume/Timeout=5
  #     -> hypridle listener timeout=300 + before_sleep_cmd=hyprlock;
  #   plasma-manager input.touchpads (disableWhileTyping/tapToClick/
  #   naturalScroll/twoFinger для GZ302EA vendorId=0b05 productId=1a30)
  #     -> input:kbd:touchpad_* опции programs.hyprland.settings.input
  #        (Hyprland читает libinput напрямую, квирк ASUS из
  #        specific/asus-input.nix остаётся действующим — он DE-независим);
  #   powerdevil-lid-fix (LidAction=0, экран гаснуть при блокировке)
  #     -> не нужен: lid обрабатывает logind, гашение делает hypridle.
  #
  # Профили производительности (AC=battery=balanced/powerSaving пороги 20/5%)
  # живут в PPD + z13ctl (specific/performance.nix) — DE-независимо, ничего
  # дублировать не нужно. Виджет батареи из Plasma заменяет waybar (ниже).
  # =====================================================================

  programs.hyprland = {
    enable = true;

    settings = {
      # === Ввод (порт plasma-manager input.touchpads для GZ302EA) ===
      input = {
        kb_layout = "us,ru";          # раскладка была в Plasma-профиле; сохраняем
        follow_mouse = 1;

        touchpad = {
          # disableWhileTyping — по умолчанию ON в libinput; фиксируем явно.
          disable_while_typing = true;
          # tapToClick=true
          tap-to-click = true;
          # naturalScroll=true
          natural_scroll = true;
          # scrollMethod="twoFinger"
          scroll_method = "two_finger";
        };
      };

      # === Прочее базовое (минимальная рабочая сессия) ===
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration = {
        rounding_power = 2;
      };

      # === Клавиши (аналоги KDE-глобалок) ===
      bind = [
        "SUPER, RETURN, exec, foot"                          # Konsole -> foot
        "SUPER, SPACE, exec, fuzzel"                         # KRunner -> fuzzel
        "CTRL ALT, L, exec, hyprlock"                        # ручной лок (KScreensaver)
        "SUPER SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"  # Spectacle region -> clipboard
        "SUPER, B, exec, waypaper --random"                  # обои (plasma wallpaper)
        ", Print, exec, grim $HOME/Pictures/screenshot-$(date +%F-%H%M%S).png"  # PrintScreen (Spectacle)
        # История буфера (Klipper): fuzzel-меню cliphist + вставка через wl-copy.
        "SUPER, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
      ];
      # Закрытие крышки: локальный дубль logind-пути (lid-daemon дергает
      # loginctl lock-sessions; этот бинд реагирует на событие Hyprland).
      bindl = [ ", switch:on:Lid Switch, exec, hyprlock" ];
    };
  };

  # Waybar — замена панели Plasma: часы, батарея (аналог виджета батарейки,
  # через который переключаются PPD-профили), трей (blueman/nm-applet/caffeine-ng).
  programs.waybar = {
    enable = true;
    settings = [{
      layer = "top";
      position = "top";
      height = 30;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "custom/power-profile" "network" "battery" "tray" ];

      # Переключение PPD-профилей кликом по модулю — тот же backend,
      # что у KDE-виджета (power-profiles-daemon D-Bus), синхронизация
      # TDP/вентиляторов — z13-ppd-sync (specific/performance.nix).
      "custom/power-profile" = {
        format = "⚡ {}";
        exec = "${pkgs.writeShellScript "ppd-active" ''
          busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile | tr -d '"' | awk '{print $2}'
        ''}";
        on-click = "$HOME/.local/bin/z13-cycle-profile";
        interval = 10;
      };
      battery = {
        format = "{capacity}% {icon}";
        tooltip = true;
      };
      network = {
        format-wifi = "{essid} ({signalStrength}%) ";
        tooltip-format = "{ifname}: {ipaddr}/{cidr}";
      };
      tray = { spacing = 10; };
      clock = { format = "{:%H:%M %d.%m}"; };
    }];
  };

  # =====================================================================
  # hypridle / hyprlock как пользовательские сервисы.
  #
  # В Home Manager есть готовые модули services.hypridle и programs.hyprlock —
  # они включают systemd-user-юниты; конфиги берём из NixOS-слоя
  # (ui/hyprland/hypridle.nix пишет /etc/hypridle.conf, hyprlock.nix —
  # /etc/hypr/hyprlock.conf), поэтому здесь только включение без дублирования.
  # before_sleep_cmd в NixOS-модуле гарантирует блокировку перед сном
  # (аналог LockOnResume + D-Bus Lock связки logind+kscreenlocker).
  # =====================================================================
  services.hypridle.enable = true;
  programs.hyprlock.enable = true;

  # Автозапуск полиkit-агента Hyprland (запросы пароля админа в GUI-приложениях;
  # в KDE это делал kcheckpass/polkit-kde-agent).
  # hyprpolkitagent запускается самой сессией Hyprland (auto-launch) — доп. юнит не нужен.

  # history of clipboard (Klipper replacement) lives in ./cliphist-hyprland.nix
  # (подключается диспетчером home-specific/default.nix).

  # Кликабельное переключение профилей PPD через mako-нет: привяжем к колесу
  # мыши над модулем батареи нельзя — вместо этого хоткей Super+P циклично
  # меняет профиль (аналог выпадашки виджета KDE).
  home.file.".local/bin/z13-cycle-profile".source = pkgs.writeShellScript "z13-cycle-profile" ''
    # Циклическое переключение power-profiles-daemon: power-saver -> balanced -> performance.
    # Аналог меню виджета батареи Plasma; backend тот же (PPD), синхронизация TDP — z13-ppd-sync.
    cur=$(busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile | tr -d '"' | awk '{print $2}')
    case "$cur" in
      power-saver) next=balanced ;;
      balanced)    next=performance ;;
      *)           next=power-saver ;;
    esac
    busctl --system call net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles SetActiveProfile s "$next"
  '';
}
