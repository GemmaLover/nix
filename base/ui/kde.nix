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

  # === Настройка LibInput для тачпада ===
  # Принудительно включаем функцию "отключение при наборе текста".
  # lib.mkForce гарантирует, что эта настройка не будет переопределена
  # другими модулями или настройками KDE.
  services.libinput = {
    enable = lib.mkForce true;
    touchpad = {
      disableWhileTyping = lib.mkForce true;
    };
  };

  # === Квирк (Quirk) для ASUS Z13 ===
  # Это специальное правило для libinput, которое сообщает системе,
  # что клавиатура является внутренней. Это необходимо для корректной
  # работы функции "отключение тачпада при наборе текста".
  # Vendor ID 0b05 = ASUSTeK.
  environment.etc."libinput/local-overrides.quirks".text = ''
    [ASUS Z13 Keyboard]
    MatchVendor=0x0B05
    MatchUdevType=keyboard
    AttrKeyboardIntegration=internal
  '';
}
