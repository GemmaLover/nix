{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # Кастомное ядро 7.2.8.
  #
  # В ветке nixos-unstable на момент настройки доступно только 7.2.7,
  # но в 7.2.8 исправлен критический баг в TTM (use-after-free после
  # гибернации) и добавлены фиксы для amdgpu на Strix Halo. Поэтому
  # собираем 7.2.8 вручную поверх linux_latest.
  #
  # version и modDirVersion должны совпадать.
  # src — тарбол с kernel.org.
  # sha256 = lib.fakeHash — заглушка. При первой сборке Nix выдаст
  # ошибку hash mismatch и покажет правильный хэш. Скопируйте его
  # и подставьте вместо lib.fakeHash.
  # =====================================================================
  customKernel = pkgs.linuxPackagesFor (pkgs.linux_latest.override {
    argsOverride = rec {
      version = "7.2.8";
      modDirVersion = version;
      src = pkgs.fetchurl {
        url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
        sha256 = "sha256-EujVqXPRrXxaXGmILkAisTHtcV23AD/c12Dd+MPlGUE=";
      };
    };
  });
in
{
  # === Ядро ===
  # Используем собранное вручную ядро 7.2.8 (вместо linuxPackages_latest,
  # который пока указывает на 7.2.7 в текущем снимке nixpkgs).
  boot.kernelPackages = customKernel;

  # === Параметры ядра для AMD GPU ===
  # Эти параметры необходимы для работы LLM на полной скорости
  # и для стабильной гибернации на Strix Halo.
  boot.kernelParams = [
    # Размер GTT-памяти (в МБ). ~111 ГБ для 128 ГБ RAM.
    "amdgpu.gttsize=113777"
    # Лимит страниц TTM. Соответствует ~111 ГБ.
    "ttm.pages_limit=29126912"
    # Увеличивает таймаут VPE (Video Processing Engine) до 2 секунд.
    # Устраняет soft lock после resume из гибернации на Strix Halo
    # (известный баг, проявляющийся в ~8% случаев).
    "amdgpu.vpe_idle_timeout=2000"
    # Отключение IOMMU снижает задержки при доступе GPU к памяти.
    "amd_iommu=off"
    # ПРИМЕЧАНИЕ: параметр asus_wmi.fnlock_default убран, так как
    # на GZ302EA он не работает (Fn-Lock управляется через HID-отчёт,
    # см. pkgs/z13-fnlock и сервис asus-fnlock).
  ];

  # === Модули ядра ===
  # kvm-amd — для виртуализации (Android Studio, Waydroid, LLM-контейнеры).
  # asus_wmi — для ASUS-специфичных функций (подсветка, профили).
  boot.kernelModules = [ "kvm-amd" "asus_wmi" ];

  # === Специализация CachyOS LTO 7.2.8 ===
  # Создаёт отдельную запись в меню systemd-boot. Выбор этой записи
  # загружает систему с ядром CachyOS (LTO, latest). Все остальные
  # настройки наследуются из основной конфигурации.
  #
  # ВАЖНО: ядра из overlay доступны как pkgs.cachyosKernels.*
  # Вариант linuxPackages-cachyos-latest-lto соответствует
  # LTO-сборке ядра 7.2.8 (проверено через `nix flake show`).
  specialisation.cachyos-lto.configuration = {
    inheritParentConfig = true;
    boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto;
  };
}
