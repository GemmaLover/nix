{ config, lib, pkgs, ... }:

{
  # === Тачпад — системный уровень libinput ===
  # На KDE/Wayland эти опции могут переопределяться plasma-manager,
  # но системный default задаём здесь.
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
  # udev ошибочно помечает тачпад GZ302EA как external.
  # libinput ориентируется на это udev-свойство, а не на quirks,
  # когда решает, включать ли disable-while-typing.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="input", \
      ATTRS{name}=="ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad", \
      ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
  '';
}
