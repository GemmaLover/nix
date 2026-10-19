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
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3090beta7";

  # Arch-пакет с официального сайта AIMP (native Linux beta).
  # Содержимое:
  #   opt/aimp/     — бинарь AIMP, плагины, скины, System/ (некоторые .so)
  #   usr/lib/      — приватные библиотеки: libbass-aimp.so, libav*.so*
  #   usr/share/    — .desktop-файлы и иконки
  #
  # Ключевое отличие от беты 3089: в 3088 и 3087 файлы libbass/libav лежат
  # в usr/lib/, а в 3089 — их нет вообще (AIMP поломал сборку).
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

     # --- НОВЫЕ ЗАВИСИМОСТИ ДЛЯ ЗВУКА ---
  alsa-lib
  libpulseaudio
  soxr
  ];

  # Приватные библиотеки AIMP лежат в $out/usr/lib/ и грузятся через
  # LD_LIBRARY_PATH wrapper-обёрток. autoPatchelfHook их не находит —
  # игнорируем на этапе проверки.
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

    # opt/ — сам AIMP (бинарь, ресурсы, плагины).
    cp -r opt $out/

    # usr/ — ВАЖНО: здесь usr/lib/ с приватными библиотеками AIMP
    # (libbass-aimp.so, libavcodec-aimp.so.61 и др.) и usr/share/
    # с .desktop-файлами. Копируем ЦЕЛИКОМ, не удаляем после.
    [ -d usr ] && cp -r usr $out/ || true

    # Дублируем usr/share → share для NixOS (иначе .desktop не найдётся).
    # usr/lib оставляем на месте — он нужен для LD_LIBRARY_PATH.
    if [ -d "$out/usr/share" ]; then
      mkdir -p "$out/share"
      cp -r "$out/usr/share/." "$out/share/"
      # usr/ НЕ удаляем — там usr/lib с приватными .so
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
    mkdir -p $out/bin

    # === КЛЮЧЕВОЙ МОМЕНТ: LD_LIBRARY_PATH ===
    # Приватные библиотеки AIMP лежат в $out/usr/lib/ (не в opt/aimp/!).
    # autoPatchelfHook перезаписал RPATH бинарника на пути Nix store и
    # стёр оригинальный $ORIGIN. Поэтому добавляем $out/usr/lib в
    # LD_LIBRARY_PATH — линкер проверит его раньше RPATH и найдёт
    # libbass-aimp.so, libavcodec-aimp.so.61 и т.д.
    commonWrapArgs="--prefix LD_LIBRARY_PATH : $out/usr/lib \
      --prefix LD_LIBRARY_PATH : $out/opt/aimp \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ curl openssl nghttp2 libssh2 libpsl brotli glib alsa-lib libpulseaudio soxr ]} \
      --prefix XDG_DATA_DIRS : ${hicolor-icon-theme}/share \
      --prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name} \
      --prefix GIO_EXTRA_MODULES : ${glib}/lib/gio/modules \
      --set GDK_PIXBUF_MODULE_FILE ${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp $commonWrapArgs
    [ -x "$out/opt/aimp/AIMPate" ] && makeWrapper $out/opt/aimp/AIMPate $out/bin/aimp-ate $commonWrapArgs || true
    [ -x "$out/opt/aimp/AIMPac" ] && makeWrapper $out/opt/aimp/AIMPac $out/bin/aimp-ac $commonWrapArgs || true

    # Патч .desktop для AIMPate/AIMPac (используем --replace, не --replace-fail).
    for desktop in "$out"/share/applications/aimpate.desktop \
                   "$out"/share/applications/aimpac.desktop; do
      [ -f "$desktop" ] || continue
      substituteInPlace "$desktop" \
        --replace "/opt/aimp/AIMPate" "$out/bin/aimp-ate" \
        --replace "/opt/aimp/AIMPac" "$out/bin/aimp-ac" \
        --replace "/usr/bin/aimp-ate" "$out/bin/aimp-ate" \
        --replace "/usr/bin/aimp-ac" "$out/bin/aimp-ac"
    done

    # Создаём aimp.desktop (в Arch-пакете он пустой).
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
