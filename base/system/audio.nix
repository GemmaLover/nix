{ config, lib, pkgs, ... }:

{
  # === Звук ===
  # PipeWire — современный звуковой сервер, заменяет PulseAudio
  services.pulseaudio.enable = false;

  # rtkit — realtime-kit для приоритетов аудио-потоков
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;          # Поддержка ALSA
    alsa.support32Bit = true;    # 32-битные ALSA-приложения (для Steam/Wine)
    pulse.enable = true;         # Совместимость с PulseAudio
    # jack.enable = true;       # Раскомментировать, если нужен JACK
  };
}
