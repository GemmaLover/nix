{ config, lib, pkgs, ... }:

{
  # === Тачпад ===
  # Базовые настройки libinput.
  services.libinput = {
    enable = true;
    touchpad = {
      disableWhileTyping = true;
      tapping = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
    };
  };

  # === Quirks для ASUS Z13 ===
  # libinput не знает, что клавиатура и тачпад — внутренние
  # устройства ASUS, поэтому disableWhileTyping не работает.
  # Этот файл помечает оба как internal и связывает их в один кластер.
  #
  # Vendor 0b05 = ASUSTeK
  # Product 1a30 = GZ302EA (клавиатура + тачпад, разные интерфейсы)
  environment.etc."libinput/local-overrides.quirks".text = ''
    [ASUS Z13 Keyboard — internal]
    MatchVendor=0x0B05
    MatchProduct=0x1A30
    MatchUdevType=keyboard
    AttrKeyboardIntegration=internal

    [ASUS Z13 Touchpad — internal]
    MatchVendor=0x0B05
    MatchProduct=0x1A30
    MatchUdevType=touchpad
    AttrTouchpadIntegration=internal
  '';
}
