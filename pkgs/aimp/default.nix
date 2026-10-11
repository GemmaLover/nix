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

  # Приватные библиотеки AIMP (лежат в $out/opt/aimp/, грузятся через $ORIGIN).
  # autoPatchelfHook не может их найти — игнорируем.
  autoPatchelfIgnoreMissingDeps = [
    "libbass-aimp.so"
    "libavcodec-aimp.so.61"
    "libavutil-aimp.so.59"
  ];

  # Распаковка .pkg.tar.zst (Arch-формат) через zstd.
  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    # opt/ — сам AIMP (бинарь, ресурсы, плагины).
    cp -r opt $out/

    # usr/ — .desktop-файлы, иконки (с префиксом usr/share).
    [ -d usr ] && cp -r usr $out/ || true

    # === Перенос usr/share → share ===
    # Arch-пакет кладёт .desktop и иконки в usr/share/...
    # NixOS ищет их в $out/share/... (без префикса usr).
    # Без этого переноса ярлыки не появятся в меню KDE.
    if [ -d "$out/usr/share" ]; then
      mkdir -p "$out/share"
      cp -r "$out/usr/share/." "$out/share/"
      rm -rf "$out/usr"
    fi

    # Симлинк на libcurl.so.4 в директории AIMP — AIMP ищет её в $ORIGIN.
    ln -sf "${lib.getLib curl}/lib/libcurl.so.4" "$out/opt/aimp/libcurl.so.4"

    runHook postInstall
  '';

  preFixup = ''
    # libcurl.so.4 нужен в DT_NEEDED главного бинарника AIMP.
    patchelf --add-needed libcurl.so.4 $out/opt/aimp/AIMP
  '';

  postFixup = ''
    # === Wrapper-обёртки для трёх исполняемых файлов AIMP ===
    # Без обёрток команды не работают из PATH и не находят curl/GTK.
    mkdir -p $out/bin

    commonWrapArgs="--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib ]} \
      --prefix XDG_DATA_DIRS : ${hicolor-icon-theme}/share \
      --prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name} \
      --prefix GIO_EXTRA_MODULES : ${glib}/lib/gio/modules \
      --set GDK_PIXBUF_MODULE_FILE ${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp $commonWrapArgs
    [ -x "$out/opt/aimp/AIMPate" ] && makeWrapper $out/opt/aimp/AIMPate $out/bin/aimp-ate $commonWrapArgs || true
    [ -x "$out/opt/aimp/AIMPac" ] && makeWrapper $out/opt/aimp/AIMPac $out/bin/aimp-ac $commonWrapArgs || true

    # === Патч существующих .desktop от AIMPate и AIMPac ===
    # ВАЖНО: используем --replace (НЕ --replace-fail). С -fail первое
    # несовпадение паттерна прерывает всю команду, и последующие
    # замены в этом файле не применяются.
    for desktop in "$out"/share/applications/aimpate.desktop \
                   "$out"/share/applications/aimpac.desktop; do
      [ -f "$desktop" ] || continue
      substituteInPlace "$desktop" \
        --replace "/opt/aimp/AIMPate" "$out/bin/aimp-ate" \
        --replace "/opt/aimp/AIMPac" "$out/bin/aimp-ac" \
        --replace "/usr/bin/aimp-ate" "$out/bin/aimp-ate" \
        --replace "/usr/bin/aimp-ac" "$out/bin/aimp-ac"
    done

    # === Создаём aimp.desktop с нуля ===
    # В Arch-пакете aimp.desktop приходит пустым (0 байт) — вероятно,
    # это артефакт их сборки. Поэтому пишем его сами.
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
