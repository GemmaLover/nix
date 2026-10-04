{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # ui/hyprland/home.nix — домашний (Home Manager) слой оси Hyprland.
  #
  # Подключается диспетчером devices/z13/home-specific/default.nix при
  # kdaOpts.ui = "hyprland" (файл лежит в ui/, чтобы DE-специфичные
  # домашние настройки были рядом с системными; путь относительный).
  # ВАЖНО: это HM-модуль — в системные imports его класть нельзя.
  #
  # Здесь — сам композитор (programs.hyprland), конфиг hyprlock и
  # пользовательские пакеты-аналоги KDE-компонентов:
  #   konsole          -> foot           (Wayland-терминал)
  #   Spectacle        -> grim + slurp   (скриншоты области/экрана)
  #   klipper          -> cliphist       (менеджер буфера обмена)
  #   Kvantum/GTK-тема -> nwg-look / gtk3 / qt6ct (выбор тем)
  #   plasmadiscover   -> не нужен (flatpak уже в base/tools/flatpak.nix)
  # =====================================================================
in
{
  # NOTE: это ДОМАШНИЙ (Home Manager) модуль — подключается из
  # devices/z13/home-specific/default.nix, а НЕ из системного default.nix.
  wayland.windowManager.hyprland = {
    enable = true;
    # Конфиг генерируется Home Manager'ом в ~/.config/hypr/hyprland.conf.
    settings = {
      # --- Базовая эстетика (порт ощущения Plasma: тёмная тема) ---
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(89b4faee)";
        "col.inactive_border" = "rgba(45475aff)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur.enabled = true;
        drop_shadow = false;
      };

      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 7, myBezier"
          "fadeIn, 1, 7"
          "fadeOut, 1, 7"
          "border, 1, 10, default"
        ];
      };

      # --- Ингибирование сна видео: аналог caffeine-ng (KDE) ---
      # Hyprland сам держит inhibit для полноэкранного видео — отдельный
      # трей-апп на этой оси не нужен (см. комментарий в home-specific/default.nix).
      # NOTE: правило "fullscreen" для firefox убрано при ревью — форсировать
      # полный экран браузеру нельзя; ингибирует только реальная полноэкранность.
      windowrulev2 = [
        "inhibit_idle fullscreen, class:^(firefox)$"
        "inhibit_idle fullscreen, class:^(chromium|google-chrome-stable)$"
        "suppression: focus_lost_for_seconds, 30"
      ];

      # --- Клавиши (аналоги плазмавых глобальных хоткеев) ---
      bind = [
        "SUPER, RETURN, exec, foot"
        "SUPER, Q, killactive,"
        "SUPER SHIFT, M, exit,"
        "SUPER, D, exec, wofi --show drun"
        # Скриншот области (аналог Spectacle-регона): grim -g "$(slurp)".
        "SHIFT, Print, exec, ${pkgs.grim}/bin/grim -g \$(${pkgs.slurp}/bin/slurp) - | ${pkgs.wl-clipboard}/bin/wl-copy"
        # Скриншот всего экрана в буфер.
        ", Print, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
        # Блокировка вручную (SUPER+L — как в KDE).
        "SUPER, L, exec, loginctl lock-session"
        # Профили PPD горячими клавишами (аналог виджета батарейки).
        "SUPER CTRL, KP_1, exec, ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver"
        "SUPER CTRL, KP_2, exec, ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced"
        "SUPER CTRL, KP_3, exec, ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance"
      ];

      # Громкость/яркость через wpctl/brightnessctl — общие утилиты.
      bind = [
        ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 5%+"
        ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume 5%-"
        ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl s 10%+"
        ", XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl s 10%-"
      ];

      # Буфер обмена с историей (аналог klipper): wl-paste | cliphist.
      exec = [
        "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
        "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
      ];

      # Автозапуск компаньонов трея (bluedevil/nm-tray из KDE -> blueman/nm-applet).
      exec-once = [
        "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"
        "${pkgs.blueman}/bin/blueman-applet"
        "${pkgs.mako}/bin/mako"              # нотификации вместо kded-плазмы
        "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk"
      ];

      # Переменные окружения сессии (как в /etc/environment, но локально).
      env = [
        "GTK_THEME, Adwaita-dark"
        "XCURSOR_SIZE, 24"
        "HYPRCURSOR_THEME, hyprgrass"
        "QT_QPA_PLATFORMTHEME, qt6ct"
      ];
    };
  };

  # --- hyprlock: конфиг локера (порт кастомизации kscreenlocker) ---
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        # Разблокировка по паролю (PAM-сервис hyprlock включён системно,
        # см. ui/hyprland/hyprland.nix).
        ignore_empty_passwords = false;
        no_fade_in = false;
      };

      # Фон с блюром — аналог кастомизации kscreenlocker.
      background = [{
        path = "file://#20202e";   # сплошной цвет, скриншот не требуется
        color = "rgba(20,20,30,0.95)";
        blur = true;
      }];

      # Индикатор ввода пароля.
      inputfield = [{
        monitor = "";
        size = "300, 60";
        outline_thickness = 2;
        dots_size = 0.2;
        dots_spacing = 0.2;
        outer_color = "rgb(8b8b8b)";
        inner_color = "rgb(24,24,34)";
        font_color = "rgb(205,214,244)";
        fade_on_empty = true;
        placeholder_text = "<i>Пароль…</i>";
        hide_input = false;
        position = "0, -120";
        halign = "center";
        valign = "center";
      }];

      # Часы на экране блокировки.
      label = [{
        monitor = "";
        text = "$TIME";
        color = "rgb(205,214,244)";
        font_size = 55;
        font_family = "Noto Sans Display Bold";
        position = "0, 300";
        halign = "center";
        valign = "center";
      }];
    };
  };

  # --- Пользовательские пакеты, заменяющие KDE-компоненты ---
  home.packages = with pkgs; [
    foot                      # Wayland-терминал (консоль KDE заменена)
    grim slurp                # скриншоты (Spectacle)
    cliphist                  # история буфера обмена (klipper)
    wofi                      # лаунчер (Alt+F2/Kickoff)
    mako                      # сервер уведомлений (kded notifications)
    networkmanagerapplet      # трей сети (plasma-networkmanagement)
    blueman                   # трей Bluetooth (bluedevil)
    brightnessctl             # регулировка яркости
    qt6ct                     # настройка Qt-тем (аналог System Settings)
    nwg-look                  # настройка GTK-тем
    hyprpicker                # пипетка цвета (KColorChooser)
  ];

  # foot — минимальная конфигурация (тёмная тема как в Plasma).
  programs.foot = {
    enable = true;
    settings = {
      main = { term = "foot"; font = "JetBrainsMono:size=11"; };
      colors = {
        background = "1e1e2e";
        foreground = "cdd6f4";
      };
    };
  };

  # Менеджер уведомлений mako: пороги/таймауты как в Plasma.
  services.mako = {
    enable = true;
    defaultTimeout = 8000;
    borderColor = "#89b4fa";
    backgroundColor = "#1e1e2ecc";
  };
}
