{ config, lib, pkgs, ... }:

{
  # === Пользователи ===
  users.users."lexi" = {
    isNormalUser = true;
    description = "lexi";
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
    ];
    # Пакеты, установленные только для этого пользователя
    packages = with pkgs; [
      kdePackages.kate   # Текстовый редактор Kate (от KDE)
    ];
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
