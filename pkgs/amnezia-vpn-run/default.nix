{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  # Скачиваем официальный .run файл с GitHub.
  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  # Распаковываем .run как обычный архив (7z, tar.gz и т.д.),
  # не выполняя встроенный установочный скрипт.
  amnezia-extracted = pkgs.stdenv.mkDerivation {
    pname = "amnezia-extracted";
    inherit version;

    src = amnezia-run;

    # .run — не стандартный архив, распаковываем вручную.
    dontUnpack = true;

    # 7z и libarchive нужны для извлечения встроенного архива.
    nativeBuildInputs = [ pkgs.p7zip pkgs.libarchive ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/amnezia
      cd $out/share/amnezia

      # Пытаемся извлечь 7z-архив, который обычно встроен в .run.
      # Флаг -y отвечает "да" на все запросы (перезапись и т.п.).
      # Если 7z не справится, пробуем bsdtar (libarchive) — он
      # автоматически определяет формат.
      7z x -y "$src" -o"$out/share/amnezia" || \
        bsdtar -xf "$src" -C "$out/share/amnezia"

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

  # Путь к бинарнику может отличаться после распаковки.
  # Если AmneziaVPN лежит в подпапке, поправьте путь (см. проверку ниже).
  runScript = "${amnezia-extracted}/share/amnezia/AmneziaVPN";
}
