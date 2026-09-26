{ config, lib, pkgs, ... }:

{
  # === Тачпад ===
  services.libinput = {
    enable = true;
    touchpad = {
      disableWhileTyping = true;
      tapping = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
    };
  };

  # === Udev-правило для тачпада ASUS Z13 ===
  # udev ошибочно помечает тачпад GZ302EA как external, из-за чего
  # libinput отключает функцию disable-while-typing.
  # Переопределяем ID_INPUT_TOUCHPAD_INTEGRATION на internal.
  # Это надёжнее quirks libinput: libinput читает именно это udev-свойство.
  services.udev.extraRules = ''
    # ASUS Z13 Touchpad: пометить как internal.
    ACTION=="add|change", SUBSYSTEM=="input", \
      ATTRS{name}=="ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad", \
      ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
  '';
}
