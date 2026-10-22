{ config, lib, pkgs, ... }:

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
}
