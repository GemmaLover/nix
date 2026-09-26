{ config, lib, pkgs, ... }:

{
  # === Ядро ===
  # Используем последнее ядро для лучшей поддержки нового оборудования (AMD Halo Strix)
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # === Параметры ядра для AMD GPU ===
  # Эти параметры необходимы для работы LLM на полной скорости.
  # amdgpu.gttsize — размер GTT-памяти (в МБ), рекомендуется 113777 МБ (~111 ГБ)
  # ttm.pages_limit — лимит страниц TTM, рекомендуется 29126912
  boot.kernelParams = [
    "amdgpu.gttsize=113777"
    "ttm.pages_limit=29126912"
    "amdgpu.vpe_idle_timeout=2000"
    "amd_iommu=off"
  ];

  # === Модули ядра ===
  # Загружаем модуль для AMD KVM (виртуализация)
  boot.kernelModules = [ "kvm-amd" ];
}
