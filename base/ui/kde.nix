{ config, lib, pkgs, ... }:

{
  # === KDE Plasma 6 ===
  # Включаем X11 (даже если используем Wayland — некоторые приложения требуют X11)
  services.xserver.enable = true;

  # SDDM — менеджер входа в систему
  services.displayManager.sddm.enable = true;

  # KDE Plasma 6
  services.desktopManager.plasma6.enable = true;

  # Печать (CUPS)
  services.printing.enable = true;

  # === Настройки экрана ===
  # Запрет засыпания при просмотре видео в Firefox/VLC
  # Это делается через настройки KDE (Power Management)
  # Можно добавить вручную в ~/.config/powermanagementprofilesrc
  # Или через systemd-ингибиторы

  # === Горячие клавиши ===
  # Переключение раскладки по CapsLock уже настроено в keyboard.nix
}
