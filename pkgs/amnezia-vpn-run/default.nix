{ pkgs ? import <nixpkgs> { } }:

let
  version = "5.0.3.0";

  amnezia-run = pkgs.fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    hash = "sha256-AzXyZD9YxNdJS+TG1HWCV0+n5aRjRQ6aR7DFwu2nl8I=";
  };

  amnezia-extracted = pkgs.stdenv.mkDerivation {
    pname = "amnezia-extracted";
    inherit version;

    src = amnezia-run;

    dontUnpack = true;

    # Инструменты для извлечения архива из .run файла.
    nativeBuildInputs = with pkgs; [
      gnutar
      gzip
      gnugrep
      coreutils
      p7zip
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/amnezia
      cd $out/share/amnezia

      # Ищем строку с маркером __ARCHIVE_BELOW__, после которой
      # начинается встроенный архив.
      ARCHIVE_LINE=$(grep -n '^__ARCHIVE_BELOW__$' $src | cut -d: -f1)

      if [ -z "$ARCHIVE_LINE" ]; then
        echo "Маркер __ARCHIVE_BELOW__ не найден. Пробуем 7z..."
        7z x -y "$src" -o"$out/share/amnezia" || \
          bsdtar -xf "$src" -C "$out/share/amnezia"
      else
        echo "Маркер найден на строке $ARCHIVE_LINE. Извлекаем архив..."
        # Извлекаем всё, что идёт после маркера, и распаковываем как tar.gz.
        # Если архив не gzip, попробуем без -z.
        tail -n +$((ARCHIVE_LINE + 1)) "$src" | tar -xzf - -C "$out/share/amnezia"
      fi

      runHook postInstall
    '';
  };

in
pkgs.buildFHSEnv {
  name = "amnezia-vpn";

  targetPkgs = pkgs: with pkgs; [
    qt6.qtbase
    qt6.qtwayland
    qt6.qt5compat

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

    libpulseaudio
    alsa-lib
    libsecret

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

  # Путь к бинарнику может отличаться. После сборки проверьте:
  # find /nix/store/*amnezia-extracted*/ -name AmneziaVPN
  runScript = "${amnezia-extracted}/share/amnezia/AmneziaVPN";
}
