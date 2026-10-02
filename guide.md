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

## 5. Структура конфига (после рефакторинга)

Конфигурация собирается из четырёх ортогональных осей:

| Слой | Что содержит | Зависит от |
|---|---|---|
| `base/` | сеть, DNS (sing-box + zapret), boot, LUKS, users, базовое ПО (`base/tools`) | ничего — общая база для всех устройств |
| `ui/` | оконная оболочка: `ui/common/` (Wayland-порталы, libinput, CUPS — при любой DE), `ui/kde/` (Plasma 6, SDDM, caffeine), `ui/hyprland/` (каркас) | только от DE |
| `devices/<name>/` | железо: `hardware.nix`, ядро, udev-правила, vendor-утилиты (`specific/`); домашний слой (`home.nix`, `home-specific/`) | от устройства (+ DE для home-specific) |
| `llm/`, `games/`, `dev/` | необязательные профили ПО, подключаются осью `kda.opts.profiles` | только от наличия профиля |

Устройство объявляет свои оси в `devices/<name>/config.nix`:

```nix
kda.opts = {
  ui = "kde";                  # kde | hyprland | none
  profiles = [ "dev" "llm" ];  # + "games" при необходимости
};
```

Диспетчеры `ui/default.nix` и `profiles/default.nix` подключают модули по этим
осям; ноды `flake.nix` собираются фабрикой `lib/mkSystem.nix`
(`mkSystem "<имя>" { deviceModule = ./devices/<имя>/config.nix; userHome = ...; }`).

Правило: всё, что привязано к vendor ID / конкретному железу, живёт в
`devices/*/specific/`; всё, что привязано к DE, — в `ui/kde/` или
`ui/hyprland/`; DE-специфичные пользовательские сервисы — в
`devices/*/home-specific/` (подключаются по оси `ui`).

## 6. Миграция на Hyprland (карта компонентов)

Переход для устройства = смена `kda.opts.ui = "hyprland"` плюс перенос
home-модулей. Системный слой `ui/common/` не меняется.

| KDE-компонент | Аналог в Hyprland | Где лежит |
|---|---|---|
| SDDM | greetd + tuigreet | `ui/hyprland/hyprland.nix` (уже) |
| Plasma Wayland-сессия | `programs.hyprland` | `ui/hyprland/hyprland.nix` (уже) |
| xdg-desktop-portal-kde | xdg-desktop-portal-hyprland (+ gtk fallback) | `ui/hyprland/hyprland.nix` + `ui/common/wayland.nix` |
| PowerDevil (крышка/профили) | systemd-logind (уже в base) + PPD + hypridle | `devices/<n>/home-specific/power-lock-hyprland.nix` (TODO) |
| kscreenlocker | hyprlock | там же (TODO) |
| caffeine-ng (трей) | `systemd-inhibit` / inhibit-rules hypridle | `devices/<n>/home-specific/caffeine-hyprland.nix` (TODO) |
| kbd-backlight-lock-sync (D-Bus org.kde.screensaver) | слушать сокет hyprlock (`socket2.sock`, event `locked`/`unlocked`), вызов asusctl тот же | `devices/<n>/home-specific/asus-backlight-hyprland.nix` (TODO) |
| bluedevil | blueman / networkmanager-applet | `ui/hyprland/` (по вкусу) |
| plasma-manager (kcminputrc) | конфиг input в hyprland.conf; libinput-квирки ASUS остаются в `devices/z13/specific/` без изменений | — |

Чек-лист: разложить `devices/z13/home-specific/*-kde.nix` на `-hyprland`
варианты, раскомментировать соответствующие ветки в
`devices/z13/home-specific/default.nix`, затем сменить ось в `config.nix`.

## 7. Следующие шаги

1. **Замените `hardware.nix`** на ваш актуальный `hardware-configuration.nix`.
2. **Проверьте UUID** в `hardware.nix` — они должны совпадать с текущей системой.
3. **Выполните сборку:**
   ```bash
   sudo nixos-rebuild switch --flake ~/nix#z13
