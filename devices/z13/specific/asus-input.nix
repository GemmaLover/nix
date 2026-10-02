{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # devices/z13/specific/asus-input.nix — ASUS-специфичный ввод.
  #
  # Перенесено из base/ui/kde.nix: libinput-квирк с Vendor ID 0b05
  # (ASUSTeK) не имеет отношения ни к KDE, ни к «базе» — это свойство
  # конкретного железа. Теперь live в слое устройства и останется
  # на месте при миграции z13 на Hyprland.
  #
  # Квирк сообщает libinput, что клавиатура GZ302EA внутренняя —
  # без него disable-while-typing не работает (тачпад не «глушится»
  # при наборе текста).
  # =====================================================================
  environment.etc."libinput/local-overrides.quirks".text = ''
    [ASUS Z13 Keyboard]
    MatchVendor=0x0B05
    MatchUdevType=keyboard
    AttrKeyboardIntegration=internal
  '';
}
