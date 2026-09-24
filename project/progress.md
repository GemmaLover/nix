# Прогресс проекта

## Статус: В работе

### Этап 1: Базовая структура ✅
- [x] Создан `flake.nix`
- [x] Созданы базовые модули `base/system/`, `base/ui/`, `base/tools/`
- [x] Создан `devices/z13/config.nix`
- [x] Создан `devices/z13/hardware.nix`
- [x] Создан `devices/z13/specific/kernel.nix`
- [x] Создан `devices/z13/specific/asus-tools.nix`
- [x] Созданы заглушки для `devices/pc/` и `devices/asus5304uv/`
- [x] Создан `dev/dev.nix`
- [x] Создан `llm/llm.nix`
- [x] Создан `games/games.nix` (TODO)

### Этап 2: Базовые настройки системы 🔄
- [x] Сеть (NetworkManager)
- [x] DNS (dnscrypt-proxy2)
- [x] Пользователи (lexi, группы)
- [x] Клавиатура (US/RU, CapsLock)
- [x] Шифрование LUKS
- [x] AppArmor (режим обучения)
- [x] Звук (PipeWire)
- [ ] Wi-Fi (настраивается через NetworkManager)
- [ ] Горячие клавиши (частично)

### Этап 3: UI и рабочий стол 🔄
- [x] KDE Plasma 6
- [x] SDDM
- [x] Тачпад (блокировка при печати)
- [ ] Управление подсветкой клавиатуры (скрипт в разработке)
- [ ] Блокировка засыпания при видео (TODO)

### Этап 4: Программы 🔄
- [x] Base tools (vim, git, firefox и др.)
- [x] Flatpak (Amnezia, ProtonVPN, Android Studio)
- [x] Dev (Podman, Docker, Waydroid)
- [x] LLM (скрипты для Podman)
- [ ] Games (Steam, Lutris, Heroic)

### Этап 5: Специфика Z13 🔄
- [x] Параметры ядра (amdgpu.gttsize, ttm.pages_limit)
- [x] asusctl
- [ ] z13-tablet-kit (TODO)
- [ ] z13ctl-plus (TODO)
- [ ] z13gui-plus (TODO)

### Этап 6: Проектные файлы 🔄
- [x] `project/progress.md` (этот файл)
- [ ] `project/problems.md`
- [ ] `project/agents.md`
- [ ] `guide.md`

### Текущая задача: Завершить настройку подсветки клавиатуры и добавить игры
