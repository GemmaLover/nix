{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  amnezia-wrapper = pkgs.writeShellScript "amnezia-vpn-wrapper" ''
    set -euo pipefail

    INSTALL_DIR="$HOME/.local/share/amnezia"
    BIN="$INSTALL_DIR/AmneziaVPN"

    if [ ! -x "$BIN" ]; then
      echo "=== AmneziaVPN не установлен ==="
      echo "Запускаю установщик. Целевая директория: $INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"

      # Копируем .run в writable-директорию, потому что /nix/store read-only.
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
        echo "Попробуйте запустить вручную:"
        echo "  $TMPDIR/amnezia.run --prefix $INSTALL_DIR"
        exit 1
      fi
    fi

    exec "$BIN" "$@"
  '';

in
pkgs.buildFHSEnv {
  name = "amnezia-vpn";

  # Библиотеки и утилиты, доступные внутри FHS-окружения.
  # Критически важны glibc и zlib — без них ELF-установщик
  # BitRock не запустится (cannot open libz.so.1, no ld-linux).
  targetPkgs = pkgs: with pkgs; [
    # Базовые библиотеки для ELF-интерпретатора и линковки.
    glibc
    zlib
    stdenv.cc.cc.lib       # libstdc++, libgcc_s
    libxcrypt              # libcrypt

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

    # Сетевые утилиты для работы VPN
    iproute2
    iptables
    iputils
    openvpn
    wireguard-tools
    sudo
    gawk
    procps
    coreutils

    # Утилиты, нужные установщику
    bash
    findutils
    gnugrep
    gnused
    gnutar
    gzip
    xz
  ];

  runScript = amnezia-wrapper;
}
