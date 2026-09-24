# Прогресс проекта

Последнее обновление: 2026-09-24

Легенда:
- [x] — реализовано и проверено
- [~] — частично реализовано (есть рабочий каркас, но не всё)
- [ ] — не начато
- [!] — сломано или требует срочного внимания

---

## 1. Инфраструктура

- [x] Flake с каналом `nixos-26.05`
- [x] Home Manager (интегрирован как модуль NixOS)
- [x] Disko (подключён как модуль, но в конфиге пока не используется)
- [x] Git-репозиторий `https://github.com/GemmaLover/nix.git`
- [x] `flake.lock` с зафиксированными ревизиями

## 2. Структура конфига

- [x] `base/system/` — общие системные настройки
- [x] `base/ui/` — KDE
- [x] `base/tools/` — базовые пакеты
- [~] `base/system/scripts/` — только `keyboard-backlight-idle` (не работает, TODO)
- [x] `devices/z13/` — конфиг текущего устройства
- [ ] `devices/pc/` — заглушка
- [ ] `devices/asus5304uv/` — заглушка
- [x] `dev/` — podman, docker, waydroid, python
- [~] `llm/` — только комментарии с планами, образов нет
- [ ] `games/` — папка отсутствует
- [x] `project/` — есть, но не полная

## 3. Базовые настройки системы (base/system)

- [x] `boot.nix` — systemd-boot, лимит 10 поколений
- [~] `network.nix` — `services.sing-box.enable = false` (временно отключён, нет конфига)
- [x] `time.nix` — Europe/Moscow, NTP-синхронизация
- [~] `network.nix` — `services.sing-box.enable = true`, но `settings` пустой
- [x] `users.nix` — lexi (wheel, networkmanager, kvm, libvirt)
- [x] `keyboard.nix` — US/RU, переключение по CapsLock, `caps:escape`
- [~] `luks.nix` — файл-заглушка, реальные настройки в `hardware.nix`
- [x] `apparmor.nix` — включён, режим обучения
- [x] `audio.nix` — PipeWire, rtkit
- [x] `dns.nix` — `dnscrypt-proxy` с quad9/cloudflare/scaleway
- [x] `touchpad.nix` — `disableWhileTyping`, тап-клик, two-finger scroll
- [~] `scripts/default.nix` — скрипт подсветки есть, но с TODO
- [ ] `scripts/` — нет скриптов для засыпания при видео
- [ ] `scripts/` — нет скриптов для LLM-контейнеров
- [ ] `scripts/` — нет деинсталлятора z13-утилит

## 4. UI (base/ui)

- [x] `kde.nix` — KDE Plasma 6, SDDM, CUPS
- [x] Блокировка засыпания при просмотре видео (caffeine-ng / встроенная KDE)
- [ ] Дополнительные горячие клавиши (кроме раскладки)

## 5. Программы (base/tools)

- [x] `base.nix` — vim, tree, file, which, wget, curl, unzip, git, htop, btop
- [x] `base.nix` — firefox, libreoffice, vlc, keepassxc, qbittorrent, obs-studio
- [x] `base.nix` — kdePackages.kleopatra, krita, librewolf, brave, putty, zenmap, parabolic
- [ ] `base.nix` — sublime4 (удалён: требует небезопасный openssl-1.1.1w, см. P-2)
- [ ] `base.nix` — AIMP (не добавлен)
- [ ] `base.nix` — Portmaster / safing.io (не добавлен)
- [x] `flatpak.nix` — модуль включён, Flathub подключён
- [ ] `flatpak.nix` — приложения (Amnezia, ProtonVPN, Android Studio) не установлены декларативно

## 6. Dev

- [x] Podman (rootless, autoPrune, dns_enabled)
- [x] Docker (overlay2)
- [x] Waydroid (nftables)
- [x] Python 3, pip
- [x] wl-clipboard

## 7. LLM

- [ ] Podman-образ Unsloth
- [ ] Podman-образ DeepSeek Harness
- [ ] Ярлык «запуск Unsloth + открыть»
- [ ] Ярлык «закрыть Unsloth + остановить podman»
- [ ] Ярлык «запуск dsharness + открыть web»
- [ ] Ярлык «закрыть dsharness + остановить podman»
- [x] Пользователь в группах kvm/libvirt (для доступа к /dev/kvm)

## 8. Games

- [ ] `games/games.nix` — папка и модуль отсутствуют
- [ ] Steam
- [ ] Lutris
- [ ] Heroic Games Launcher

## 9. Специфика Z13

- [x] `kernel.nix` — amdgpu.gttsize=113777, ttm.pages_limit=29126912
- [x] `kernel.nix` — boot.kernelPackages = linuxPackages_latest
- [x] `asus-tools.nix` — asusctl + services.asusd (без asusd-user)
- [x] `asus-tools.nix` — /etc/asusd через tmpfiles
- [ ] `z13-tablet-kit` — не установлен
- [ ] `z13ctl-plus` — не установлен
- [ ] `z13gui-plus` — не установлен
- [ ] Скрипт-деинсталлятор для z13-утилит
- [x] Скрипт отключения подсветки через 15 секунд простоя (через swayidle + systemd user services)
- [x] Статичная белая подсветка без пульсации (asusctl aura effect static -c ffffff, leds set low)

## 10. Другие устройства

- [ ] `devices/pc/` — PC AMD + NVIDIA (TODO)
- [ ] `devices/asus5304uv/` — ASUS Intel (TODO)

## 11. Проектные файлы

- [x] `project/user_input.md` — ТЗ
- [x] `project/progress.md` — этот файл
- [x] `project/problems.md` — заведён
- [ ] `project/agents.md`
- [ ] `project/projcet.md` — список всех требований (генерируется из user_input.md)
- [ ] `project/log/consoleYYYYMMDD.log` — логи команд не ведутся
- [ ] `guide.md` — содержимое не выверено

---

## Текущая задача

Подсветка клавиатуры и блокировка засыпания завершены.

## Следующая задача

Программы: Flatpak-приложения (Amnezia, ProtonVPN, Android Studio).
