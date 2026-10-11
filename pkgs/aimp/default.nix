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

  # Arch-пакет с официального сайта AIMP (native Linux beta).
  # Содержит бинарь в opt/aimp/, .desktop и иконки в usr/share/.
  # Распаковывается через zstd (не tar.gz).
  src = fetchurl {
      url = "https://www.aimp.ru/files/windows/builds/aimp-nightly-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    patchelf
    zstd
  ];

  # Библиотеки, от которых зависит AIMP (GTK3, curl, sqlite, аудио).
  # autoPatchelfHook прописывает их в RPATH.
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

  # Распаковка .pkg.tar.zst (Arch-формат) через zstd.
  # Стандартный unpackPhase не умеет с zstd, поэтому явно.
  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    # opt/ — тут сам AIMP (бинарь, ресурсы, плагины).
    # Это стандартный путь Arch-пакета: /opt/aimp/AIMP.
    cp -r opt $out/

    # usr/ — тут .desktop-файл, иконки, но с префиксом usr/share.
    # Просто копируем, чтобы ничего не потерять.
    [ -d usr ] && cp -r usr $out/ || true

    # === КЛЮЧЕВОЙ МОМЕНТ ===
    # Arch-пакет кладёт .desktop и иконки в usr/share/...
    # NixOS ищет их в $out/share/... (без префикса usr).
    # Без этого переноса ярлык AIMP не появится в меню KDE.
    # Переносим содержимое usr/share в $out/share, сохраняя структуру,
    # затем удаляем usr, чтобы не оставлять мёртвый путь.
    if [ -d "$out/usr/share" ]; then
      mkdir -p "$out/share"
      cp -r "$out/usr/share/." "$out/share/"
      rm -rf "$out/usr"
    fi

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
    # Без этого AIMP падает при старте с "libcurl.so.4: not found".
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    # Создаём wrapper /bin/aimp — чтобы команда `aimp` работала из PATH.
    # wrapper выставляет LD_LIBRARY_PATH и GDK_PIXBUF_MODULE_FILE,
    # иначе AIMP не находит curl/GTK/иконки.
    mkdir -p $out/bin
    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib ]}" \
      --prefix XDG_DATA_DIRS : "${hicolor-icon-theme}/share" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --prefix GIO_EXTRA_MODULES : "${glib}/lib/gio/modules" \
      --set GDK_PIXBUF_MODULE_FILE "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    # Патчим .desktop — теперь файл точно в $out/share/applications.
    # Arch-пакет прописывает Exec=/opt/aimp/AIMP, заменяем на наш wrapper
    # ($out/bin/aimp), потому что /opt/aimp в NixOS не существует.
    if [ -f "$out/share/applications/aimp.desktop" ]; then
      substituteInPlace "$out/share/applications/aimp.desktop" \
        --replace-fail "/opt/aimp/AIMP" "$out/bin/aimp" \
        --replace-fail "/usr/bin/aimp" "$out/bin/aimp" || true

      # Фоллбэк: если Exec=aimp (без пути) — тоже заменяем на наш.
      if ! grep -q "$out/bin/aimp" "$out/share/applications/aimp.desktop"; then
        substituteInPlace "$out/share/applications/aimp.desktop" \
          --replace-fail "Exec=aimp" "Exec=$out/bin/aimp" || true
      fi
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
