{ lib, writeScriptBin, python3 }:

# Обёртка через writeScriptBin — самый простой способ
# положить python-скрипт в store как исполняемый файл.
writeScriptBin "z13-fnlock" ''
  #!${python3}/bin/python3
  """Переключает Fn-Lock на ASUS ROG Flow Z13 (N-Key клавиатура).

  Отправляет HID feature report напрямую в /dev/hidraw* устройство
  N-Key клавиатуры. Формат из патчей ядра:
    enable  (F1-F12 primary):  0x5a 0xd0 0x4e 0x01
    disable (media primary):   0x5a 0xd0 0x4e 0x00
  """
  import argparse
  import fcntl
  import os
  import sys
  from pathlib import Path

  # HIDIOCSFEATURE ioctl из linux/hidraw.h.
  # _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x06, len)
  def hidio_csfeature(length: int) -> int:
      return (3 << 30) | (length << 16) | (ord('H') << 8) | 0x06

  def find_nkey_hidraw():
      """Ищем hidraw-устройство N-Key клавиатуры по имени."""
      for hidraw in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
          uevent = hidraw / "device" / "uevent"
          try:
              content = uevent.read_text()
          except OSError:
              continue
          if "N-KEY" in content.upper() or "NKEY" in content.upper():
              return f"/dev/{hidraw.name}"
      return None

  def set_fnlock(enabled: bool) -> int:
      device = find_nkey_hidraw()
      if not device:
          print("N-Key hidraw не найден", file=sys.stderr)
          return 1

      # Feature report: report id + payload.
      report = bytes([0x5a, 0xd0, 0x4e, 0x01 if enabled else 0x00])

      try:
          fd = os.open(device, os.O_RDWR)
      except PermissionError:
          print(f"Нет доступа к {device}. Запустите через sudo.", file=sys.stderr)
          return 1

      try:
          fcntl.ioctl(fd, hidio_csfeature(len(report)), report)
      except OSError as e:
          print(f"ioctl ошибка: {e}", file=sys.stderr)
          return 1
      finally:
          os.close(fd)

      state = "включён (F1-F12 primary)" if enabled else "выключен (media primary)"
      print(f"Fn-Lock {state}")
      return 0

  def main() -> int:
      parser = argparse.ArgumentParser(description="ASUS Z13 Fn-Lock toggle")
      parser.add_argument(
          "state",
          choices=["on", "off", "enable", "disable"],
          help="on/enable — F1-F12 primary; off/disable — media primary",
      )
      args = parser.parse_args()
      enabled = args.state in ("on", "enable")
      return set_fnlock(enabled)

  if __name__ == "__main__":
      sys.exit(main())
''
