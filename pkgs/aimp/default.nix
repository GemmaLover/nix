{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, patchelf
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
, glib
, at-spi2-core
, fontconfig
, freetype
, zlib
, nghttp2
, libssh2
, libpsl
, brotli
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3089beta7";

  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3089beta7-1-x86_64.pkg.tar.zst";
    hash = "sha256-9kHs6Qfw8+lfDqZdghfdkKVJT2LT6xLaoaGkzskv/9k=";
  };

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
  ];

  # Приватные библиотеки AIMP (libbass-aimp.so, libavcodec-aimp.so и др.)
  # лежат в $out/opt/aimp/ и грузятся через RPATH=$ORIGIN. autoPatchelfHook
  # их не найдёт в стандартных путях — это нормально, они не патчатся.
  autoPatchelfIgnoreMissingDeps = [
    "libbass-aimp.so"
    "libavcodec-aimp.so.61"
    "libavutil-aimp.so.59"
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # Перенос usr/share → share (иначе NixOS не видит .desktop).
    if [ -d "$out/usr/share" ]; then
      mkdir -p "$out/share"
      cp -r "$out/usr/share/." "$out/share/"
      rm -rf "$out/usr"
    fi

    ln -sf "${lib.getLib curl}/lib/libcurl.so.4" "$out/opt/aimp/libcurl.so.4"

    runHook postInstall
  '';

  preFixup = ''
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    mkdir -p $out/bin

    # === КЛЮЧЕВОЙ МОМЕНТ ===
    # autoPatchelfHook перезаписывает RPATH бинарника на пути Nix store
    # и ТЕРЯЕТ оригинальный $ORIGIN. AIMP через $ORIGIN ищет свои приватные
    # библиотеки (libbass-aimp.so, libavcodec-aimp.so.61, libavutil-aimp.so.59)
    # в директории рядом с бинарём ($out/opt/aimp/). После патча он их
    # не находит и падает с "libbass-aimp.so: cannot open shared object file".
    #
    # Лечение: добавить $out/opt/aimp в LD_LIBRARY_PATH через wrapper.
    # Динамический линкер смотрит LD_LIBRARY_PATH ДО RPATH, поэтому
    # приватные библиотеки будут найдены в директории AIMP.
    commonWrapArgs="--prefix LD_LIBRARY_PATH : $out/opt/aimp \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib ]} \
      --prefix XDG_DATA_DIRS : ${hicolor-icon-theme}/share \
      --prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name} \
      --prefix GIO_EXTRA_MODULES : ${glib}/lib/gio/modules \
      --set GDK_PIXBUF_MODULE_FILE ${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp $commonWrapArgs
    [ -x "$out/opt/aimp/AIMPate" ] && makeWrapper $out/opt/aimp/AIMPate $out/bin/aimp-ate $commonWrapArgs || true
    [ -x "$out/opt/aimp/AIMPac" ] && makeWrapper $out/opt/aimp/AIMPac $out/bin/aimp-ac $commonWrapArgs || true

    # Патч .desktop для AIMPate/AIMPac.
    for desktop in "$out"/share/applications/aimpate.desktop \
                   "$out"/share/applications/aimpac.desktop; do
      [ -f "$desktop" ] || continue
      substituteInPlace "$desktop" \
        --replace "/opt/aimp/AIMPate" "$out/bin/aimp-ate" \
        --replace "/opt/aimp/AIMPac" "$out/bin/aimp-ac" \
        --replace "/usr/bin/aimp-ate" "$out/bin/aimp-ate" \
        --replace "/usr/bin/aimp-ac" "$out/bin/aimp-ac"
    done

    # Создаём aimp.desktop (в Arch-пакете он пустой, 0 байт).
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
