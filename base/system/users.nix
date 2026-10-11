{ config, lib, pkgs, ... }:

{

 # =====================================================================
  # Управление паролями
  # =====================================================================
  # mutableUsers = false:
  #   NixOS жёстко управляет /etc/shadow из этого конфига при каждом
  #   nixos-rebuild. Ручные `passwd` не выживают.
  #
  #   Зачем: при дефолте (true) NixOS применяет hashedPassword только
  #   один раз при создании пользователя, дальше не отслеживает.
  #   Из-за этого ручной `sudo passwd root` тихо перезаписывает пароль,
  #   и конфиг перестаёт соответствовать реальности. С false такого нет.
  #
  #   Минус: `passwd` для смены пароля не работает — только через
  #   правку этого файла + nixos-rebuild.
  users.mutableUsers = false;
  # === Пользователи ===
  users.users.root.hashedPassword = "$6$V7DATbxGeLD62uWF$UHymFJn2.A0Tu0KYtpXC8OWUhkb546qSowpljSdKxVyThD0UoLAuOgaTYyIyzIL4IzR7tdlM2BA2sb.iyxlt9.";

  users.users."lexi" = {
    isNormalUser = true;
    description = "lexi";
    hashedPassword = "$6$GPL8EsRB2L1Bdcpa$wWBefGGAX7oypoVBuC.CvhjaM2fpc7tsAuN8S7HEedtfhVjb9pK8bUrTV0gIj7RKAUo1MIITOFNPFA.L8j1Hl0";

    # Группы:
    # - networkmanager: управление сетевыми подключениями
    # - wheel: sudo-права
    # - kvm: доступ к /dev/kvm для виртуализации
    # - libvirt: управление виртуальными машинами
    extraGroups = [
      "networkmanager"
      "wheel"
      "kvm"
      "libvirt"
      "video"
      "render"
    ];
    # Пакеты, установленные только для этого пользователя
    packages = with pkgs; [
      kdePackages.kate   # Текстовый редактор Kate (от KDE)
    ];

    #Диапазоны UID/GID для rootless Podman.
    # Без них контейнеры не смогут запуститься.
    autoSubUidGidRange = true;
  };

  # === sudo ===
  # Включаем sudo для группы wheel
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;  # Требовать пароль для sudo
  };

  # === KVM ===
  # Доступ к /dev/kvm для ускорения виртуализации
  # (нужно для Android Studio, Waydroid, LLM-контейнеров)
}
