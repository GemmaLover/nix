# ВАЖНО: это Home Manager-модуль. programs.hyprland здесь НЕЛЬЗЯ —
# HM-опция programs.hyprland существует только когда включён модуль
# NixOS programs.hyprland.enable (home-manager.sharedModules), а он у нас
# выключен при ui = "hyprland" (см. ui/hyprland/hyprland.nix). Конфиг
# ~/.config/hypr/hyprland.conf генерирует отдельный модуль ./hyprland-conf.nix.
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
  #        обрабатывает logind + lid-демон — см. devices/z13/config.nix,
  #        таймаутов suspend здесь НЕТ намеренно);
  #   kscreenlockerrc Autolock/LockOnResume/Timeout=5
  #     -> hypridle listener timeout=300 + before_sleep_cmd=hyprlock;
  #   plasma-manager input.touchpads (disableWhileTyping/tapToClick/
  #   naturalScroll/twoFinger для GZ302EA vendorId=0b05 productId=1a30)
  #     -> блок input:touchpad в ~/.config/hypr/hyprland.conf
  #        (см. ./hyprland-conf.nix; Hyprland читает libinput напрямую,
  #        квирк ASUS из specific/asus-input.nix остаётся действующим —
  #        он DE-независим);
  #   powerdevil-lid-fix (LidAction=0, экран гаснуть при блокировке)
  #     -> не нужен: lid обрабатывает logind, гашение делает hypridle.
  #
  # Профили производительности (AC=battery=balanced/powerSaving пороги 20/5%)
  # живут в PPD + z13ctl (specific/performance.nix) — DE-независимо, ничего
  # дублировать не нужно. Виджет батареи из Plasma заменяет waybar (ниже).
  # =====================================================================

  # Пакеты окружения Hyprland (сами хоткеи/ввод — в ./hyprland-conf.nix,
  # чтобы не требовать включения NixOS programs.hyprland.enable):
  #   foot      — терминал (аналог Konsole)
  #   fuzzel    — лаунчер/меню (аналог KRunner)
  #   grim slurp — скриншоты области (аналог Spectacle)
  #   wl-clipboard — wl-copy/paste для пайпов хоткеев
  #   waybar    — панель (часы/батарея/трей вместо Plasma-плазм)
  home.packages = with pkgs; [
    foot
    fuzzel
    grim
    slurp
    wl-clipboard
    cliphist
    waybar
  ];

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
  # hypridle / hyprlock — ПОЛНОСТЬЮ в Home Manager.
  #
  # Почему не в NixOS-слое: модулей `services.hypridle` и
  # `programs.hyprlock.settings` в nixpkgs НЕ СУЩЕСТВУЕТ (у NixOS-
  # programs.hyprlock только enable/package) — прошлая версия этих
  # файлов в ui/hyprland/ падала на eval с «The option
  # programs.hyprlock.settings does not exist». Оба модуля живут в HM:
  #   services.hypridle        -> ~/.config/hypr/hypridle.conf + user-юнит
  #   programs.hyprlock        -> ~/.config/hypr/hyprlock.conf
  # Конфиги ниже — порт поведения PowerDevil+kscreenlocker
  # (бывший ui/hyprland/hypridle.nix / hyprlock.nix, удалены).
  # =====================================================================
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        # Перед сном/гибернацией (logind lid-путь) — заблокировать экран:
        # аналог LockOnResume + D-Bus Lock в связке logind+kscreenlocker.
        before_sleep_cmd = "hyprlock --quiet & sleep 1";
        # После пробуждения — включить дисплеи (dpms мог быть выключен).
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        # 5 минут бездействия → блокировка (аналог kscreenlockerrc Timeout=5).
        {
          timeout = 300;
          # hyprlock запускается прямым бинарём: PATH user-юнита содержит
          # home.packages, XDG_RUNTIME_DIR подставляет systemd-user-окружение.
          on-timeout = "hyprlock --quiet";
          # Разблокировка → снова активен (аналог ActiveChanged=false).
          on-resume = "";
        }
        # Сразу после блокировки (клавиатура hyprlock перехвачена) —
        # погасить экран: аналог TurnOffDisplayIdleTimeoutWhenLockedSec=1,
        # который в KDE приходилось форсировать сервисом powerdevil-lid-fix.
        {
          timeout = 1;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        # 20 минут общего простоя от сети → гарантированно OFF
        # (аналог AC turnOffDisplay.idleTimeout = 1200 в PowerDevil).
        {
          timeout = 1200;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # Экран блокировки (аналог kscreenlocker Greeter): blur + поле пароля + часы.
  programs.hyprlock = {
    enable = true;
    settings = {
      # Общее: не отключать greeter (показываем нативный UI hyprlock).
      general = {
        disable_greeter = false;
      };

      # Затемнение фона (аналог размытия kscreenlocker).
      background = {
        color = "rgba(20,20,30,0.95)";
        blur = true;
      };

      # input-field — список блоков в hyprlock.conf; HM-модуль принимает list.
      input-field = [ {
        size = "250, 60";
        outline_thickness = 2;
        dots_size = 0.2;
        dots_spacing = 0.2;
        outer_color = "rgb(60,60,80)";
        inner_color = "rgb(30,30,45)";
        font_color = "rgb(220,220,230)";
        fade_on_empty = false;
        placeholder_text = "<i>Password...</i>";
        hide_input = false;
        position = "0, -25";
        halign = "center";
        valign = "center";
      } ];

      # Часы над полем ввода (аналог виджета времени на lock-экране Plasma).
      label = [ {
        text = "cmd[update:3600000] date +'%H:%M'";
        color = "rgba(230,230,240,0.95)";
        font_size = 72;
        font_family = "Noto Sans";
        position = "0, 120";
        halign = "center";
        valign = "center";
      } ];
    };
  };

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
