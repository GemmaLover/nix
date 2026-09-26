{ config, lib, pkgs, ... }:

{
  # === Тачпад ===
  # Базовые настройки libinput. KDE может их переопределять,
  # но quirk ниже заставит libinput считать клавиатуру внутренней.
  services.libinput = {
    enable = true;
    touchpad = {
      # Отключать тачпад, пока нажата клавиша на клавиатуре.
      # Это системная настройка; KDE может её перебивать,
      # поэтому дополнительно используем quirk.
      disableWhileTyping = true;
      tapping = true;
      naturalScrolling = true;
      scrollMethod = "twofinger";
    };
  };

  # === Quirk для ASUS Z13 ===
  # libinput не знает, что клавиатура ASUS — внутренняя, и не
  # применяет disableWhileTyping. Этот файл это исправляет.
  # Vendor 0b05 = ASUSTeK, Product 1a30 = GZ302EA-Keyboard.
  environment.etc."libinput/local-overrides.quirks".text = ''
    [ASUS Z13 Keyboard]
    MatchVendor=0x0B05
    MatchProduct=0x1A30
    MatchUdevType=keyboard
    AttrKeyboardIntegration=internal
  '';
}
