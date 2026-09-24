{ config, lib, pkgs, ... }:

{
  # === Flatpak ===
  # Flatpak позволяет устанавливать приложения в песочнице с минимальными правами
  services.flatpak.enable = true;

  # Добавляем репозиторий Flathub для всех пользователей
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };

  # === Flatpak-приложения ===
  # Эти приложения устанавливаются через Flatpak с минимальными правами.
  # Установка происходит при первом запуске или вручную:
  # flatpak install flathub com.amnezia.AmneziaVPN
  # flatpak install flathub com.protonvpn.ProtonVPN
  # flatpak install flathub com.google.AndroidStudio
}
