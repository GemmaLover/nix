{ config, lib, pkgs, ... }:

{
  # === Загрузчик systemd-boot ===
  # Используется на всех наших устройствах (UEFI).
  # systemd-boot проще, чем GRUB, и не требует указания диска
  # (в отличие от GRUB), потому что устанавливается в ESP
  # (EFI System Partition), которая уже смонтирована в /boot.
  boot.loader.systemd-boot.enable = true;

  # Разрешить NixOS изменять EFI-переменные загрузки.
  # Нужно, чтобы systemd-boot регистрировался как основной загрузчик
  # и обновлял записи при новых поколениях.
  boot.loader.efi.canTouchEfiVariables = true;

  # === Ограничение количества поколений ===
  # Храним только последние 10 поколений системы — экономит место в /boot.
  # Старые можно откатить при загрузке, но обычно хватает 10.
  boot.loader.systemd-boot.configurationLimit = 10;

   # === systemd в initrd ===
  # Включает современный systemd-based initrd вместо legacy bash-скриптов.
  # Критически важно для корректной работы гибернации на LUKS:
  # systemd умеет правильно упорядочивать разблокировку шифрованных
  # устройств и resume из swap. Без этого возможны зависания при
  # пробуждении и долгая загрузка.
  boot.initrd.systemd.enable = true;

  # === Гибернация ===
  # Включает сервисы управления питанием, необходимые для hibernate.
  powerManagement.enable = true;
}
