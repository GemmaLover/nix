{ config, lib, pkgs, ... }:

{
  # === Тачпад ===
  # Блокировка тачпада при наборе текста — предотвращает ложные нажатия
  services.libinput = {
    enable = true;
    touchpad = {
      # Блокировать тачпад, пока нажата клавиша на клавиатуре
      disableWhileTyping = true;

      # Тап-клик (нажатие без физического нажатия)
      tapping = true;

      # Прокрутка двумя пальцами
      naturalScrolling = true;

      # Прокрутка двумя пальцами по горизонтали
      scrollMethod = "twofinger";
    };
  };
}
