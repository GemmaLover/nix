{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # ui/common/input.nix — DE-независимый ввод (libinput).
  #
  # Перенесено из base/ui/kde.nix: раньше базовые настройки тачпада
  # жили в KDE-модуле с mkForce, что ломало бы любую другую оболочку.
  # Теперь здесь только нейтральные дефолты (mkDefault) — оболочка или
  # устройство могут их переопределить.
  #
  # ВАЖНО: vendor-specific квирки (например, ASUS quirks для
  # disable-while-typing) живут НЕ здесь, а в devices/<n>/specific/ —
  # они зависят от железа, а не от оболочки.
  # =====================================================================

  services.libinput = {
    enable = true;
    touchpad = {
      disableWhileTyping = lib.mkDefault true;
      tapping = lib.mkDefault true;
      naturalScrolling = lib.mkDefault true;
      scrollMethod = lib.mkDefault "twofinger";
    };
  };
}
