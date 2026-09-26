{ lib, writeScriptBin, python3 }:

writeScriptBin "z13-fnlock" ''
  #!${python3}/bin/python3
  """Переключает Fn-Lock на ASUS ROG Flow Z13 (N-Key клавиатура).

  Отправляет HID feature report напрямую в /dev/hidraw* клавиатуры
  (Vendor 0x0B05, Product 0x1A30).

  Семантика байта (проверено эмпирически на GZ302EA):
    F1-F12 primary  -> 5A-D0-4E-00
    media primary   -> 5A-D0-4E-01
  """
  import argparse
  import fcntl
  import os
  import sys
  from pathlib import Path

  # HIDIOCSFEATURE ioctl из linux/hidraw.h.
  def hidio_csfeature(length: int) -> int:
      return (3 << 30) | (length << 16) | (ord('H') << 8) | 0x06

  def find_keyboard_hidraws():
      """Ищем hidraw-устройства клавиатуры ASUS (product 0x1a30)."""
      devices = []
      for hidraw in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
          uevent = hidraw / "device" / "uevent"
          try:
              content = uevent.read_text()
          except OSError:
              continue
          # Клавиатура ASUS: Vendor 0b05, Product 1a30.
          if "00000B05" in content and "00001A30" in content:
              devices.append(f"/dev/{hidraw.name}")
      return devices

  def set_fnlock(enabled: bool) -> int:
      """enabled=True  -> F1-F12 primary.
         enabled=False -> media primary."""
      devices = find_keyboard_hidraws()
      if not devices:
          print("Клавиатура ASUS (0b05:1a30) не найдена", file=sys.stderr)
          return 1

      # F1-F12 primary → 0x00, media primary → 0x01.
      report = bytes([0x5a, 0xd0, 0x4e, 0x00 if enabled else 0x01])

      success = False
      for device in devices:
          try:
              fd = os.open(device, os.O_RDWR)
          except PermissionError:
              print(f"Нет доступа к {device}", file=sys.stderr)
              continue
          try:
              fcntl.ioctl(fd, hidio_csfeature(len(report)), report)
              success = True
          except OSError as e:
              print(f"ioctl ошибка на {device}: {e}", file=sys.stderr)
          finally:
              os.close(fd)

      if not success:
          return 1

      state = "F1-F12 primary" if enabled else "media primary"
      print(f"Fn-Lock: {state}")
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
