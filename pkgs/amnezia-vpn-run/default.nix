{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  # Официальный .run — это ELF-исполняемый установщик (BitRock),
  # а не архив. Его нельзя распаковать, только запустить.
  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  # Обёртка, которая при первом запуске устанавливает AmneziaVPN
  # в пользовательскую директорию, а затем запускает бинарник.
  # Установщик BitRock поддерживает --mode unattended --prefix.
  amnezia-wrapper = pkgs.writeShellScript "amnezia-vpn-wrapper" ''
    set -euo pipefail

    INSTALL_DIR="$HOME/.local/share/amnezia"
    BIN="$INSTALL_DIR/AmneziaVPN"

    if [ ! -x "$BIN" ]; then
      echo "=== AmneziaVPN не установлен ==="
      echo "Запускаю установщик. Целевая директория: $INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"

      # Копируем .run в writable-директорию, потому что /nix/store
      # read-only и chmod +x там не работает.
      TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TMPDIR"' EXIT
      cp ${amnezia-run} "$TMPDIR/amnezia.run"
      chmod +x "$TMPDIR/amnezia.run"

      # --mode unattended: тихая установка без GUI.
      # --unattendedmodeui none: не показывать прогресс-бар.
      # --prefix: куда устанавливать.
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

    # Утилиты, нужные установщику BitRock
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
