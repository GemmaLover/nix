{ lib, python3, ... }:

python3.pkgs.buildPythonApplication rec {
  pname = "z13-fnlock";
  version = "1.0.0";

  # Скрипт пишем прямо в Nix — не нужен отдельный репозиторий.
  src = python3.pkgs.writeTextFile {
    name = "z13-fnlock";
    text = ''
      #!/usr/bin/env python3
      """Переключает Fn-Lock на ASUS ROG Flow Z13 (N-Key клавиатура).

      Отправляет HID feature report напрямую в /dev/hidraw* устройство
      N-Key клавиатуры. Использует формат из патчей ядра:
        enable  (F1-F12 primary):  0x5a 0xd0 0x4e 0x01
        disable (media primary):   0x5a 0xd0 0x4e 0x00
      """
      import argparse
      import fcntl
      import os
      import sys
      from pathlib import Path

      # HIDIOCSFEATURE ioctl из linux/hidraw.h.
      # Вычисляется как _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x06, len)
      HIDIOCSFEATURE = lambda length: (3 << 30) | (length << 16) | (ord('H') << 8) | 0x06

      # Ищем hidraw по имени устройства.
      def find_nkey_hidraw() -> str | None:
          for hidraw in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
              name_file = hidraw / "device" / "uevent"
              try:
                  content = name_file.read_text()
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

          # feature report: 4 байта (report id 0x5a + 3 байта данных).
          # На самом деле первый байт — это report number для HID,
          # а остальные — payload. Формат из обсуждения LKML.
          report = bytes([0x5a, 0xd0, 0x4e, 0x01 if enabled else 0x00])

          try:
              fd = os.open(device, os.O_RDWR)
          except PermissionError:
              print(f"Нет доступа к {device}. Запустите через sudo.", file=sys.stderr)
              return 1

          try:
              fcntl.ioctl(fd, HIDIOCSFEATURE(len(report)), report)
          except OSError as e:
              print(f"ioctl ошибка: {e}", file=sys.stderr)
              return 1
          finally:
              os.close(fd)

          print(f"Fn-Lock {'включён (F1-F12 primary)' if enabled else 'выключен (media primary)'}")
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
    '';
    executable = true;
  };

  # Не собираем из исходников — просто устанавливаем скрипт.
  format = "other";
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/z13-fnlock
    chmod +x $out/bin/z13-fnlock
  '';

  meta = with lib; {
    description = "Fn-Lock toggle for ASUS ROG Flow Z13 (GZ302EA)";
    license = licenses.mit;
    mainProgram = "z13-fnlock";
  };
}
