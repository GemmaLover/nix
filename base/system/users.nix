{ config, lib, pkgs, ... }:

{
  # === Пользователи ===
  users.users.root.hashedPassword = "$6$oXfnL06TMvmOp8c1$63doQt2SHhwRlwEJqmtSfmldfCM/0RvtzNIy3X.gDbjvA0G4c3FW98wmEXfMQSae56ZEzFICE/98fsqhX67Uj/";

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
