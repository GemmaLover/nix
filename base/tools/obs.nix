{ config, pkgs, ... }:

{
  # OBS Studio с виртуальной камерой и плагинами.
  # enableVirtualCamera автоматически настраивает v4l2loopback и polkit.
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-vaapi
      obs-pipewire-audio-capture
      obs-backgroundremoval
    ];
  };

  # Портал для захвата экрана/окон в Niri (PipeWire screencast).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
    config.niri.default = [ "gnome" ];
  };

  # Отключить публикацию камер через WirePlumber/libcamera.
  # Приложения, ходящие в /dev/video* напрямую (OBS), не затрагиваются.
  services.pipewire.wireplumber.extraConfig."10-disable-camera" = {
    "wireplumber.profiles" = {
      main."monitor.libcamera" = "disabled";
    };
  };
}
