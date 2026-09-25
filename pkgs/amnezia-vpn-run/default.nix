{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  # Скачиваем официальный .run файл с GitHub.
  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  # Распаковываем .run в store. --noexec извлекает только файлы,
  # не запуская установочный скрипт.
  amnezia-extracted = pkgs.stdenv.mkDerivation {
    pname = "amnezia-extracted";
    inherit version;

    src = amnezia-run;

    # .run — не стандартный архив, распаковываем вручную.
    dontUnpack = true;

    # 7z нужен, если .run использует его внутри для распаковки.
    nativeBuildInputs = [ pkgs.p7zip ];

    installPhase = ''
      runHook preInstall

      # Файлы в /nix/store read-only — копируем .run во временную
      # директорию, чтобы сделать его исполняемым.
      cp $src ./amnezia.run
      chmod +x ./amnezia.run

      mkdir -p $out/share/amnezia
      ./amnezia.run --target $out/share/amnezia --noexec

      runHook postInstall
    '';
  };

in
pkgs.buildFHSEnv {
  name = "amnezia-vpn";

  targetPkgs = pkgs: with pkgs; [
    # Qt
    qt6.qtbase
    qt6.qtwayland
    qt6.qt5compat

    # X11 / Wayland
    libxcb
    libxcb-util
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-wm
    libxcb-cursor
    libx11
    libxext
    libxinerama
    libxrender
    libxkbcommon
    libGL
    libglvnd
    wayland

    # Звук и секреты
    libpulseaudio
    alsa-lib
    libsecret

    # Сетевые утилиты, нужные Amnezia для настройки VPN.
    iproute2
    iptables
    iputils
    openvpn
    wireguard-tools
    sudo
    gawk
    procps
    coreutils
  ];

  runScript = "${amnezia-extracted}/share/amnezia/AmneziaVPN";
}
