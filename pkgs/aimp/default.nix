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
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3086beta6";

  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  # wrapGAppsHook3 убран: он создаёт свою обёртку поверх нашей
  # и стирает LD_LIBRARY_PATH. Все GTK-переменные выставляем
  # вручную через makeWrapper в postFixup.
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    patchelf
    zstd
  ];

  # curl и openssl должны быть в buildInputs, чтобы autoPatchelfHook
  # нашёл libcurl.so.4 (когда мы добавим её в DT_NEEDED через preFixup).
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
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    runHook postInstall
  '';

  # preFixup выполняется ДО autoPatchelfHook.
  # Добавляем libcurl.so.4 в DT_NEEDED — тогда autoPatchelfHook увидит
  # её как зависимость, найдёт через buildInputs и добавит curl's lib
  # в RPATH. На старте ld.so загрузит libcurl до запуска main(),
  # и AIMP'овский dlopen("libcurl.so.4") вернёт уже загруженный handle.
  preFixup = ''
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    # Обёртка с LD_LIBRARY_PATH для GTK и curl. Создаём в postFixup,
    # чтобы autoPatchelfHook больше не трогал $out/bin/aimp.
    mkdir -p $out/bin
    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ curl openssl ]}" \
      --prefix XDG_DATA_DIRS : "${hicolor-icon-theme}/share" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --prefix GIO_EXTRA_MODULES : "${glib}/lib/gio/modules" \
      --set GDK_PIXBUF_MODULE_FILE "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    # Правим .desktop-файл: путь к бинарнику.
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
