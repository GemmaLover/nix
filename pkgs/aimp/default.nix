{ lib
, stdenv
, autoPatchelfHook
, makeWrapper
, patchelf
, gtk3
, gdk-pixbuf
, cairo
, pango
, sqlite
, libogg
, libvorbis
, harfbuzz
, libappindicator-gtk3
, opus-tools
, hicolor-icon-theme
, libx11
, zstd
, curl
, openssl
, glib
, at-spi2-core
, fontconfig
, freetype
, zlib
, nghttp2
, libssh2
, libpsl
, brotli
, alsa-lib
, libpulseaudio
, soxr
, portaudio
}:

let
  portaudioWithPulse = portaudio.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ libpulseaudio ];
    configureFlags = (oldAttrs.configureFlags or [ ]) ++ [ "--with-pulseaudio" ];
  });
in
stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3090beta7";

  src = ./aimp-6.00.3090beta7-1-x86_64.pkg.tar.zst;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    patchelf
    zstd
  ];

  buildInputs = [
    gtk3
    gdk-pixbuf
    cairo
    pango
    sqlite
    libogg
    libvorbis
    harfbuzz
    libappindicator-gtk3
    opus-tools
    hicolor-icon-theme
    libx11
    curl
    openssl
    glib
    at-spi2-core
    fontconfig
    freetype
    zlib
    nghttp2
    libssh2
    libpsl
    brotli
    alsa-lib
    libpulseaudio
    soxr
    portaudioWithPulse
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libbass-aimp.so"
    "libavcodec-aimp.so.61"
    "libavutil-aimp.so.59"
    "libavfilter-aimp.so.10"
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    if [ -d "$out/usr/share" ]; then
      mkdir -p "$out/share"
      cp -r "$out/usr/share/." "$out/share/"
    fi

    # Symlink на libcurl.so.4 (AIMP ищет её в $ORIGIN).
    ln -sf "${lib.getLib curl}/lib/libcurl.so.4" "$out/opt/aimp/libcurl.so.4"

    # === Симлинки в $ORIGIN с ОБОИМИ именами (с версией и без) ===
    # AIMP/BASS вызывает dlopen("libasound.so") — БЕЗ суффикса версии.
    # Поэтому нужны и libasound.so, и libasound.so.2 в $ORIGIN.
    ln -sf "${lib.getLib alsa-lib}/lib/libasound.so.2"     "$out/opt/aimp/libasound.so"
    ln -sf "${lib.getLib alsa-lib}/lib/libasound.so.2"     "$out/opt/aimp/libasound.so.2"
    ln -sf "${lib.getLib soxr}/lib/libsoxr.so.0"           "$out/opt/aimp/libsoxr.so"
    ln -sf "${lib.getLib soxr}/lib/libsoxr.so.0"           "$out/opt/aimp/libsoxr.so.0"
    ln -sf "${lib.getLib libogg}/lib/libogg.so.0"          "$out/opt/aimp/libogg.so"
    ln -sf "${lib.getLib libogg}/lib/libogg.so.0"          "$out/opt/aimp/libogg.so.0"
    ln -sf "${lib.getLib libvorbis}/lib/libvorbis.so.0"    "$out/opt/aimp/libvorbis.so"
    ln -sf "${lib.getLib libvorbis}/lib/libvorbis.so.0"    "$out/opt/aimp/libvorbis.so.0"
    ln -sf "${lib.getLib libvorbis}/lib/libvorbisenc.so.2" "$out/opt/aimp/libvorbisenc.so"
    ln -sf "${lib.getLib libvorbis}/lib/libvorbisenc.so.2" "$out/opt/aimp/libvorbisenc.so.2"
    ln -sf "${lib.getLib libpulseaudio}/lib/libpulse.so.0" "$out/opt/aimp/libpulse.so"
    ln -sf "${lib.getLib libpulseaudio}/lib/libpulse.so.0" "$out/opt/aimp/libpulse.so.0"
    ln -sf "${lib.getLib portaudioWithPulse}/lib/libportaudio.so.2" "$out/opt/aimp/libportaudio.so"
    ln -sf "${lib.getLib portaudioWithPulse}/lib/libportaudio.so.2" "$out/opt/aimp/libportaudio.so.2"

    # Приватные AIMP .so из usr/lib — тоже в $ORIGIN, чтобы dlopen нашёл их
    # без опоры на LD_LIBRARY_PATH (AIMP его игнорирует при dlopen).
    for f in "$out"/usr/lib/libbass-aimp.so \
             "$out"/usr/lib/libavcodec-aimp.so.61 \
             "$out"/usr/lib/libavutil-aimp.so.59 \
             "$out"/usr/lib/libavfilter-aimp.so.10; do
      [ -e "$f" ] && ln -sf "$f" "$out/opt/aimp/$(basename "$f")" || true
    done

    runHook postInstall
  '';

  preFixup = ''
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    mkdir -p $out/bin

    commonWrapArgs="--prefix LD_LIBRARY_PATH : $out/usr/lib \
      --prefix LD_LIBRARY_PATH : $out/opt/aimp \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib alsa-lib libpulseaudio soxr portaudioWithPulse ]} \
      --prefix XDG_DATA_DIRS : ${hicolor-icon-theme}/share \
      --prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name} \
      --prefix GIO_EXTRA_MODULES : ${glib}/lib/gio/modules \
      --set GDK_PIXBUF_MODULE_FILE ${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp $commonWrapArgs
    [ -x "$out/opt/aimp/AIMPate" ] && makeWrapper $out/opt/aimp/AIMPate $out/bin/aimp-ate $commonWrapArgs || true
    [ -x "$out/opt/aimp/AIMPac" ] && makeWrapper $out/opt/aimp/AIMPac $out/bin/aimp-ac $commonWrapArgs || true

    for desktop in "$out"/share/applications/aimpate.desktop \
                   "$out"/share/applications/aimpac.desktop; do
      [ -f "$desktop" ] || continue
      substituteInPlace "$desktop" \
        --replace "/opt/aimp/AIMPate" "$out/bin/aimp-ate" \
        --replace "/opt/aimp/AIMPac" "$out/bin/aimp-ac" \
        --replace "/usr/bin/aimp-ate" "$out/bin/aimp-ate" \
        --replace "/usr/bin/aimp-ac" "$out/bin/aimp-ac"
    done

    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/aimp.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=AIMP
GenericName=Audio Player
Comment=AIMP audio player (native Linux beta)
Exec=$out/bin/aimp %U
Icon=aimp
Terminal=false
Categories=Audio;AudioVideo;Player;GTK;
MimeType=audio/mpeg;audio/flac;audio/ogg;audio/x-wav;audio/mp4;audio/aac;audio/x-ape;audio/x-wv;audio/x-musepack;
Keywords=audio;music;player;aimp;
EOF
  '';

  meta = with lib; {
    description = "AIMP audio player (native Linux version, beta)";
    homepage = "https://aimp.ru";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "aimp";
  };
}
