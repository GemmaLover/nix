# Руководство по установке NixOS с конфигом из Git

## Предварительные требования
- NixOS установлен на устройство
- Доступ к интернету
- Git

## Установка на чистой системе

### Шаг 1: Клонировать репозиторий
```bash
git clone https://github.com/GemmaLover/nix.git ~/nix
cd ~/nix

Шаг 2: Скопировать hardware-configuration.nix
bash

# Сгенерировать конфигурацию оборудования для текущего устройства
sudo nixos-generate-config --show-hardware-config > devices/z13/hardware.nix

Шаг 3: Проверить конфиг

Убедитесь, что в devices/z13/hardware.nix правильные UUID дисков.
Шаг 4: Применить конфигурацию
bash

sudo nixos-rebuild switch --flake .#z13

Шаг 5: Перезагрузка
bash

sudo reboot

Применение на уже установленной системе

Если NixOS уже установлен, но вы хотите применить этот конфиг:

    Клонируйте репозиторий в ~/nix

    Замените devices/z13/hardware.nix на ваш текущий hardware-configuration.nix

    Выполните:

bash

sudo nixos-rebuild switch --flake ~/nix#z13

Важно: LUKS

Если система установлена с LUKS-шифрованием, не меняйте UUID в hardware.nix.
Если UUID не совпадают — система не загрузится.
Добавление нового устройства

    Создайте папку devices/<имя>/

    Скопируйте hardware.nix с нового устройства

    Создайте config.nix по образцу devices/z13/config.nix

    Добавьте устройство в flake.nix

    Выполните sudo nixos-rebuild switch --flake .#<имя>

text


---

## 5. Следующие шаги

1. **Создайте все файлы** из этого ответа в вашем репозитории.
2. **Замените `hardware.nix`** на ваш актуальный `hardware-configuration.nix`.
3. **Проверьте UUID** в `hardware.nix` — они должны совпадать с текущей системой.
4. **Выполните сборку:**
   ```bash
   sudo nixos-rebuild switch --flake ~/nix#z13
