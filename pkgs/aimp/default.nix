{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3          # было wrapGAppsHook
, gtk3
, gdk-pixbuf
, cairo
, pango
, sqlite
, libvorbis
, harfbuzz
, libappindicator-gtk3
, opus-tools
, hicolor-icon-theme
, libx11                  # было xorg.libX11
, zstd
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3086beta6";

  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3        # здесь тоже
    zstd
  ];

  buildInputs = [
    gtk3
    gdk-pixbuf
    cairo
    pango
    sqlite
    libvorbis
    harfbuzz
    libappindicator-gtk3
    opus-tools
    hicolor-icon-theme
    libx11                # и здесь
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    mkdir -p $out/bin
    ln -sf $out/usr/bin/aimp $out/bin/aimp
    runHook postInstall
  '';

  meta = with lib; {
    description = "AIMP audio player (native Linux version)";
    homepage = "https://aimp.ru";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "aimp";
  };
}
