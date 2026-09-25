{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  # Скачиваем официальный .run файл с GitHub.
  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    # Хэш-заглушка — Nix выдаст правильный при первой сборке.
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Распаковываем .run во временную директорию в store.
  # .run — самораспаковывающийся архив, --noexec извлекает только файлы.
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

      # Целевая директория в store.
      mkdir -p $out/share/amnezia
      cd $out/share/amnezia

      # Делаем .run исполняемым и распаковываем.
      chmod +x $src
      $src --target $out/share/amnezia --noexec

      runHook postInstall
    '';
  };

in
# buildFHSEnv создаёт окружение, где бинарник видит стандартные пути
# /usr/lib, /lib и т.д., как в обычном Linux. Это снимает необходимость
# патчить каждую библиотеку.
pkgs.buildFHSEnv {
  name = "amnezia-vpn";

  # Пакеты, которые должны быть доступны внутри FHS-окружения.
  # Это библиотеки, нужные Qt-приложению, и утилиты для работы VPN.
  targetPkgs = pkgs: with pkgs; [
    # Qt
    qt6.qtbase
    qt6.qtwayland
    qt6.qt5compat

    # X11 / Wayland
    xorg.libxcb
    xorg.xcbutil
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    xorg.xcbutilcursor
    xorg.libX11
    xorg.libXext
    xorg.libXinerama
    xorg.libXrender
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

  # Что запускать при старте FHS-обёртки.
  runScript = "${amnezia-extracted}/share/amnezia/AmneziaVPN";
}
