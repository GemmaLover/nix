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
  version = "6.00.3086beta6";

  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
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

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # Кладём симлинк на libcurl.so.4 прямо в директорию AIMP.
    # AIMP ищет её в $ORIGIN (директория бинарника) через свой dlopen.
    # Используем lib.getLib curl — не ${curl}, потому что у curl
    # split output: .so файлы в -lib output, бинарники в -bin.
    ln -sf "${lib.getLib curl}/lib/libcurl.so.4" "$out/opt/aimp/libcurl.so.4"

    runHook postInstall
  '';

  preFixup = ''
    # Добавляем libcurl.so.4 в DT_NEEDED, чтобы autoPatchelfHook
    # прописал curl's lib в RPATH AIMP.
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    # Обёртка с LD_LIBRARY_PATH на все зависимости curl и GTK.
    mkdir -p $out/bin
    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib ]}" \
      --prefix XDG_DATA_DIRS : "${hicolor-icon-theme}/share" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --prefix GIO_EXTRA_MODULES : "${glib}/lib/gio/modules" \
      --set GDK_PIXBUF_MODULE_FILE "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

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
