{ config, lib, pkgs, inputs, ... }:

let
  # =====================================================================
  # ЯДРО
  #
  # Активно: linux-cachyos-latest-lto-zen4 версии 7.2.8.
  #
  # Почему именно этот вариант:
  #   - latest: свежее ядро, в текущем flake — 7.2.8 (совпадает с вашим
  #     кастомным ядром, но с патчами и оптимизациями CachyOS)
  #   - lto: Link-Time Optimization, +2–5% производительности
  #   - zen4: оптимизация под микроархитектуру Zen 4 (Ryzen AI MAX+ 395)
  #
  # ВАЖНО про оверлей: в flake.nix подключаем overlays.pinned
  # (а не overlays.default). pinned берёт nixpkgs, зашитый в самом
  # nix-cachyos-kernel, поэтому версия ядра гарантированно 7.2.8,
  # независимо от того, что в вашем nixpkgs. Если использовать default,
  # версия может «уплыть» при обновлении вашего nixpkgs.
  #
  # Кастомное ядро 7.2.8 (сборка из kernel.org) закомментировано ниже —
  # оставлено как резерв, если CachyOS по каким-то причинам не подойдёт
  # (например, регрессия в патчах или несовместимость с amdgpu).
  # =====================================================================

  # ---------------------------------------------------------------------
  # АКТИВНО: CachyOS LTO zen4 7.2.8
  # ---------------------------------------------------------------------
  cachyosKernel = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

  # ---------------------------------------------------------------------
  # ЗАКОММЕНТИРОВАНО: кастомное ядро 7.2.8 (сборка из kernel.org).
  #
  # version и modDirVersion должны совпадать.
  # src — тарбол с kernel.org.
  # sha256 — реальный хэш, уже получен при первой сборке.
  #
  # Раскомментируйте и закомментируйте cachyosKernel выше, если
  # захотите вернуться к ванильному ядру 7.2.8.
  # ---------------------------------------------------------------------
  # customKernel = pkgs.linuxPackagesFor (pkgs.linux_latest.override {
  #   argsOverride = rec {
  #     version = "7.2.8";
  #     modDirVersion = version;
  #     src = pkgs.fetchurl {
  #       url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
  #       sha256 = "sha256-EujVqXPRrXxaXGmILkAisTHtcV23AD/c12Dd+MPlGUE=";
  #     };
  #   };
  # });
in
{
  # === Ядро ===
  boot.kernelPackages = cachyosKernel;

  # === Параметры ядра для AMD GPU ===
  # Эти параметры необходимы для работы LLM на полной скорости
  # и для стабильной гибернации на Strix Halo.
  boot.kernelParams = [
    # Размер GTT-памяти (в МБ). ~111 ГБ для 128 ГБ RAM.
    "amdgpu.gttsize=126976"
    # Лимит страниц TTM. Соответствует ~111 ГБ.
    "ttm.pages_limit=32505856"
    "ttm.page_pool_size=32505856"
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

  # === Специализация CachyOS — не нужна ===
  # CachyOS теперь основное ядро, отдельная запись в systemd-boot
  # не требуется. Кастомное 7.2.8 остаётся в комментарии выше.
}
