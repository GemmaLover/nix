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

  # ВАЖНО: убрали wrapGAppsHook3 — он создаёт свою обёртку поверх нашей
  # и перезаписывает $out/bin/aimp, из-за чего shell-скрипт с
  # LD_LIBRARY_PATH пропадает. Вместо него используем makeWrapper
  # в postFixup (после fixupPhase).
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

  postFixup = ''
    # Шаг 1: жёстко прописываем DT_RPATH (не DT_RUNPATH) в сам бинарник AIMP.
    # dlopen из подгруженного .so игнорирует LD_LIBRARY_PATH — работает
    # только DT_RPATH, который мы ставим через --force-rpath.
    patchelf --force-rpath \
      --set-rpath "${lib.makeLibraryPath [ curl openssl ]}" \
      $out/opt/aimp/AIMP

    # Шаг 2: shell-обёртка через makeWrapper. Делается в postFixup,
    # чтобы autoPatchelfHook больше не трогал $out/bin/aimp.
    # Переменные GTK выставлены вручную — их раньше давал wrapGAppsHook3.
    mkdir -p $out/bin
    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ curl openssl ]}" \
      --prefix XDG_DATA_DIRS : "${hicolor-icon-theme}/share" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --prefix GIO_EXTRA_MODULES : "${glib}/lib/gio/modules" \
      --set GDK_PIXBUF_MODULE_FILE "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    # Шаг 3: правим .desktop-файл: путь к бинарнику.
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
