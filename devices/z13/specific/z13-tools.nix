{ config, lib, pkgs, ... }:

let
  # Подключаем локальные пакеты из pkgs/.
  z13ctl-plus = pkgs.callPackage ../../../pkgs/z13ctl-plus { };
  z13gui-plus = pkgs.callPackage ../../../pkgs/z13gui-plus { };
  z13-tablet-kit = pkgs.callPackage ../../../pkgs/z13-tablet-kit { };

  # Пути к утилитам, которые используются в udev-правилах и сервисах.
  # Заменяем FHS-пути (/usr/bin/...) на актуальные store-пути Nix.
  chgrp = "${pkgs.coreutils}/bin/chgrp";
  chmod = "${pkgs.coreutils}/bin/chmod";
  sh = "${pkgs.runtimeShell}";
in
{
  # === Пакеты ===
  environment.systemPackages = [
    z13ctl-plus
    z13gui-plus
    z13-tablet-kit
  ];

  # === Udev-правила из z13-tablet-kit ===
  # Дают доступ к тачпаду и тачскрину без root-прав.
  services.udev.packages = [ z13-tablet-kit ];

  # === Udev-правила для z13ctl-plus ===
  # Декларативный эквивалент `z13ctl setup`.
  # Дают группе users доступ к:
  #   - hidraw-устройствам (клавиатура 1a30, lightbar 18c6)
  #   - platform-profile (профиль производительности)
  #   - battery charge_control_end_threshold (лимит заряда)
  #   - Armoury Crate button input device
  #   - firmware-attributes (boot_sound, panel_overdrive)
  #   - hwmon fan curve
  #   - PPT power limits
  services.udev.extraRules = ''
    # --- Клавиатура и lightbar ASUS (hidraw) ---
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="18c6", MODE="0660", GROUP="users"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", MODE="0660", GROUP="users"

    # --- Профиль производительности ---
    ACTION=="add", SUBSYSTEM=="platform-profile", RUN+="${chgrp} users /sys%p/profile", RUN+="${chmod} g+w /sys%p/profile"

    # --- Лимит заряда батареи ---
    ACTION=="add", SUBSYSTEM=="platform-profile", KERNELS=="asus-nb-wmi", RUN+="${chgrp} users /sys/class/power_supply/BAT0/charge_control_end_threshold", RUN+="${chmod} g+w /sys/class/power_supply/BAT0/charge_control_end_threshold"

    # --- Кнопка Armoury Crate ---
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Asus WMI hotkeys", MODE="0660", GROUP="users"

    # --- firmware-attributes: boot_sound и panel_overdrive ---
    ACTION=="add", SUBSYSTEM=="firmware-attributes", KERNEL=="asus-armoury", RUN+="${chgrp} users /sys/class/firmware-attributes/asus-armoury/attributes/boot_sound/current_value", RUN+="${chmod} g+w /sys/class/firmware-attributes/asus-armoury/attributes/boot_sound/current_value"
    ACTION=="add", SUBSYSTEM=="firmware-attributes", KERNEL=="asus-armoury", RUN+="${chgrp} users /sys/class/firmware-attributes/asus-armoury/attributes/panel_overdrive/current_value", RUN+="${chmod} g+w /sys/class/firmware-attributes/asus-armoury/attributes/panel_overdrive/current_value"

    # --- Fan curves ---
    ACTION=="add", SUBSYSTEM=="hwmon", ATTR{name}=="asus_custom_fan_curve", RUN+="${sh} -c '${chgrp} users /sys%p/pwm*; ${chmod} g+w /sys%p/pwm*'"
    ACTION=="add", SUBSYSTEM=="hwmon", ATTR{name}=="asus", RUN+="${sh} -c 'for f in /sys%p/pwm*_enable; do [ -e \"$$f\" ] && ${chgrp} users \"$$f\" && ${chmod} g+w \"$$f\"; done'"

    # --- PPT power limits ---
    ACTION=="add", SUBSYSTEM=="platform", KERNEL=="asus-nb-wmi", RUN+="${sh} -c 'for f in /sys/devices/platform/asus-nb-wmi/ppt_*; do [ -e \"$$f\" ] && ${chgrp} users \"$$f\" && ${chmod} g+w \"$$f\"; done'"
  '';

  # === Systemd-сервис: права для поздно создаваемых sysfs-атрибутов ===
  # Некоторые атрибуты (charge_control_end_threshold, firmware-attributes,
  # PPT, cpufreq) создаются после того, как udev уже отработал.
  # Поэтому выставляем права отдельным oneshot-сервисом.
  systemd.services.z13ctl-perms = {
    description = "z13ctl-plus sysfs permissions (battery + firmware-attributes + PPT + CPU power)";

    # После sysinit.target — когда все устройства уже проинициализированы.
    after = [ "sysinit.target" ];
    wantedBy = [ "sysinit.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # Каждый ExecStart — отдельная команда. Список означает выполнение по очереди.
      ExecStart = [
        # Лимит заряда батареи.
        "${sh} -c 'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -e \"$f\" ] && ${chgrp} users \"$f\" && ${chmod} g+w \"$f\"; done'"
        # firmware-attributes: boot_sound, panel_overdrive.
        "${sh} -c 'for f in /sys/class/firmware-attributes/asus-armoury/attributes/boot_sound/current_value /sys/class/firmware-attributes/asus-armoury/attributes/panel_overdrive/current_value; do [ -e \"$f\" ] && ${chgrp} users \"$f\" && ${chmod} g+w \"$f\"; done'"
        # PPT power limits.
        "${sh} -c 'for f in /sys/devices/platform/asus-nb-wmi/ppt_*; do [ -e \"$f\" ] && ${chgrp} users \"$f\" && ${chmod} g+w \"$f\"; done'"
        # CPU power: boost, scaling_min_freq, energy_performance_preference.
        "${sh} -c 'for f in /sys/devices/system/cpu/cpufreq/boost /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do [ -e \"$f\" ] && ${chgrp} users \"$f\" && ${chmod} g+w \"$f\"; done'"
      ];
    };
  };

  # === Systemd user-сервис: демон z13ctl ===
  systemd.user.services.z13ctld = {
    description = "z13ctl device daemon for ASUS ROG Flow Z13";

    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${z13ctl-plus}/bin/z13ctl daemon";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # === Директория состояния ===
  systemd.tmpfiles.rules = [
    "d %t/z13ctl 0700 %u %g -"
  ];
}
