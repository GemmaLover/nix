{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  # Полный набор библиотек, которые могут понадобиться установщику
  # BitRock и самому приложению Amnezia. Включает всё, на чём
  # пользователь уже ловил ошибки: zlib, freetype, dbus, zstd, и т.д.
  runtimeLibs = with pkgs; [
    # Базовые системные
    glibc
    zlib
    zstd
    xz
    bzip2
    openssl
    libxcrypt
    stdenv.cc.cc.lib    # libstdc++, libgcc_s

    # D-Bus
    dbus
    dbus.lib

    # Шрифты и изображения
    freetype
    fontconfig
    expat
    libpng
    libjpeg
    giflib
    libtiff
    cairo
    pango
    gdk-pixbuf
    harfbuzz
    atk
    gtk2
    gtk3

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
    libxfixes
    libxi
    libxtst
    libxcursor
    libxrandr
    libxcomposite
    libxdamage
    libxscrnsaver
    libxkbcommon
    libGL
    libglvnd
    libGLU
    wayland

    # Звук и секреты
    libpulseaudio
    alsa-lib
    libsecret
  ];

  # Формируем LD_LIBRARY_PATH из всех runtimeLibs.
  # Это гарантирует, что динамический линкер найдёт .so файлы,
  # даже если FHS-окружение их не пробрасывает автоматически.
  libPath = pkgs.lib.makeLibraryPath runtimeLibs;

  amnezia-wrapper = pkgs.writeShellScript "amnezia-vpn-wrapper" ''
    set -euo pipefail

    INSTALL_DIR="$HOME/.local/share/amnezia"
    BIN="$INSTALL_DIR/AmneziaVPN"

    # Явно указываем, где искать библиотеки.
    export LD_LIBRARY_PATH="${libPath}:''${LD_LIBRARY_PATH:-}"

    if [ ! -x "$BIN" ]; then
      echo "=== AmneziaVPN не установлен ==="
      echo "Запускаю установщик. Целевая директория: $INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"

      TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TMPDIR"' EXIT
      cp ${amnezia-run} "$TMPDIR/amnezia.run"
      chmod +x "$TMPDIR/amnezia.run"

      "$TMPDIR/amnezia.run" \
        --mode unattended \
        --unattendedmodeui none \
        --prefix "$INSTALL_DIR" || true

      if [ ! -x "$BIN" ]; then
        echo "Автоматическая установка не удалась."
        exit 1
      fi
    fi

    exec "$BIN" "$@"
  '';

in
pkgs.buildFHSEnv {
  name = "amnezia-vpn";

  # В FHS кладём те же библиотеки, плюс утилиты для установки и VPN.
  targetPkgs = pkgs: runtimeLibs ++ (with pkgs; [
    iproute2
    iptables
    iputils
    openvpn
    wireguard-tools
    sudo
    gawk
    procps
    coreutils
    bash
    findutils
    gnugrep
    gnused
    gnutar
    gzip
    xz
    file
  ]);

  runScript = amnezia-wrapper;
}
