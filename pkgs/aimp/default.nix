{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
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
, libx11
, zstd
, curl
, openssl
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3086beta6";

  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
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
    libx11
    curl
    openssl
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # Обёртка на чистом shell — makeWrapper не работает, потому что
    # wrapGAppsHook3 выполняется позже и перезаписывает LD_LIBRARY_PATH.
    # AIMP подгружает libcurl.so.4 через dlopen() — autoPatchelfHook
    # такие библиотеки не видит. LD_LIBRARY_PATH решает проблему.
    mkdir -p $out/bin
    cat > $out/bin/aimp <<EOF
#!/bin/sh
# Обёртка AIMP для NixOS. Выставляет LD_LIBRARY_PATH для dlopen-библиотек.
export LD_LIBRARY_PATH="${lib.makeLibraryPath [ curl openssl ]}"
exec "$out/opt/aimp/AIMP" "\$@"
EOF
    chmod +x $out/bin/aimp

    runHook postInstall
  '';

  postFixup = ''
    if [ -f $out/share/applications/aimp.desktop ]; then
      substituteInPlace $out/share/applications/aimp.desktop \
        --replace "/opt/aimp/AIMP" "$out/bin/aimp" \
        --replace "/usr/bin/aimp" "$out/bin/aimp" || true
    fi
  '';

  meta = with lib; {
    description = "AIMP audio player (native Linux version, beta)";
    homepage = "https://aimp.ru";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "aimp";
  };
}
