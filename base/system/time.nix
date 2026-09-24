{ config, lib, pkgs, ... }:

{
  # === Часовой пояс ===
  # Europe/Moscow = UTC+3.
  # Устанавливается для всей системы, влияет на логи, KDE, консоль.
  time.timeZone = "Europe/Moscow";

  # === Аппаратные часы ===
  # false — часы в BIOS/UEFI хранят UTC (стандарт для Linux).
  # true — часы хранят локальное время (для dual-boot с Windows).
  # У нас Linux-only, поэтому false.
  time.hardwareClockInLocalTime = false;

  # === NTP-синхронизация ===
  # Автоматически подтягивать точное время из интернета.
  # Использует пул серверов NTP по умолчанию (time.nist.gov и др.).
  services.timesyncd.enable = true;
}
