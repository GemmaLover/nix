{ config, lib, pkgs, ... }:

{
  # === Поддержка AMD GPU (графика + ROCm/OpenCL) ===
  # Нужна для локального инференса LLM и игр.
  # Не подключать к устройствам с NVIDIA или Intel GPU.

  # Базовые настройки графики: OpenGL, Vulkan (RADV), VA-API.
  # enable32Bit нужен для Steam/Proton и 32-битных приложений.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    # OpenCL через ROCm — для LLM (PyTorch, llama.cpp и т.д.).
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  # Глобальный флаг nixpkgs: включает поддержку ROCm в пакетах,
  # которые её требуют (например, PyTorch с AMD GPU).
  nixpkgs.config.rocmSupport = true;

  # OpenCL-стек AMD (ROCm runtime) через модуль amdgpu.
  hardware.amdgpu.opencl.enable = true;

  # Утилиты для проверки Vulkan и OpenCL.
  environment.systemPackages = with pkgs; [
    vulkan-tools   # vulkaninfo, vkcube
    clinfo         # проверка OpenCL
  ];
}
