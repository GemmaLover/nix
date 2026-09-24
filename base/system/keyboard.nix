{ config, lib, pkgs, ... }:

{
  # === Раскладка клавиатуры ===
  # US по умолчанию, RU как вторая
  services.xserver.xkb = {
    layout = "us,ru";
    variant = ",";
    # Переключение раскладки по CapsLock.
    # CapsLock не включается (caps:escape — CapsLock работает как Escape,
    # а grp:caps_toggle — переключение раскладки по CapsLock).
    # Комбинация: CapsLock → переключение US/RU, без фиксации CapsLock.
    options = "grp:caps_toggle,caps:escape";
  };

  # Консольная раскладка (для TTY)
  console.keyMap = "us";
}
