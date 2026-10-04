{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # Демон, слушающий события Lid Switch через evdev.
  #
  # Читает /dev/input/event* напрямую — это обходит проблему, когда
  # PowerDevil держит ингибитор handle-lid-switch в logind и не даёт
  # ему обрабатывать крышку.
  #
  # Логика:
  #   - От сети:      loginctl lock-sessions (kscreenlocker покажет экран).
  #   - От батареи:   systemctl suspend.
  #
  # ВАЖНО: гибернация (systemctl hibernate) намеренно ОТКАЗАНА — она
  # ломала систему (проблемы с TTM/amdgpu после resume, порча данных).
  # Используем только сон (suspend-to-RAM). Не возвращать hibernate
  # без отдельной проверки.
  # =====================================================================
  lidDaemonPy = pkgs.writeText "z13-lid-daemon.py" ''
    import struct
    import os
    import sys
    import subprocess

    # Константы из <linux/input-event-codes.h>
    EV_SW = 0x05
    SW_LID = 0x00
    # Структура struct input_event: два time_t, type, code, value.
    # На x86_64 time_t — 8 байт.
    EVENT_FORMAT = 'llHHi'
    EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

    def find_lid_device():
        """Ищем /dev/input/event* с именем, содержащим 'Lid Switch'."""
        for entry in sorted(os.listdir('/sys/class/input')):
            if not entry.startswith('event'):
                continue
            name_file = f'/sys/class/input/{entry}/device/name'
            try:
                with open(name_file) as f:
                    if 'Lid Switch' in f.read():
                        return f'/dev/input/{entry}'
            except OSError:
                continue
        return None

    def get_power_source():
        """True — от сети, False — от батареи."""
        for f in ['/sys/class/power_supply/AC0/online',
                  '/sys/class/power_supply/AC/online',
                  '/sys/class/power_supply/ACAD/online']:
            try:
                with open(f) as fp:
                    return fp.read().strip() == '1'
            except OSError:
                continue
        return False

    def handle_lid_close():
        if get_power_source():
            # От сети — блокировка сессии.
            subprocess.run(['loginctl', 'lock-sessions'], check=False)
        else:
            # От батареи — сон (suspend). Гибернация отключена: ломала систему.
            subprocess.run(['systemctl', 'suspend'], check=False)

    def main():
        device = find_lid_device()
        if not device:
            print('Lid switch device not found', file=sys.stderr)
            return 1
        print(f'z13-lid-daemon: listening on {device}', flush=True)
        with open(device, 'rb') as f:
            while True:
                data = f.read(EVENT_SIZE)
                if len(data) < EVENT_SIZE:
                    break
                _, _, ev_type, ev_code, ev_value = struct.unpack(EVENT_FORMAT, data)
                # Реагируем только на "крышка закрыта" (SW_LID = 1).
                if ev_type == EV_SW and ev_code == SW_LID and ev_value == 1:
                    handle_lid_close()
        return 0

    if __name__ == '__main__':
        sys.exit(main())
  '';
in
{
  # =====================================================================
  # Демон запускается от root, потому что нужен доступ
  # к /dev/input/event* (только root может их читать).
  # =====================================================================
  systemd.services.z13-lid-daemon = {
    description = "Lid switch handler for ASUS Z13";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${lidDaemonPy}";
      Restart = "always";
      RestartSec = "5";
    };
  };
}
