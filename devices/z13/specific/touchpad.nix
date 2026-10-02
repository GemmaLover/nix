{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/specific/touchpad.nix — тачпад ASUS Z13 (GZ302EA).
  #
  # Перенесено из base/system/touchpad.nix: DE-независимые дефолты
  # libinput теперь в ui/common/input.nix, а здесь — только udev-квирк
  # конкретного железа.
  #
  # === Udev-правило для тачпада ASUS Z13 ===
  # udev ошибочно помечает тачпад GZ302EA как external.
  # libinput ориентируется на это udev-свойство, а не на quirks,
  # когда решает, включать ли disable-while-typing.
  # =====================================================================
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="input", \
      ATTRS{name}=="ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad", \
      ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
  '';
}
