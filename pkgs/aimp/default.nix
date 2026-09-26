{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
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
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3086beta6";

  # Официальный пакет AIMP 6 для Linux (Arch Linux .pkg.tar.zst).
  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  # autoPatchelfHook — правит RPATH прямых ELF-зависимостей.
  # wrapGAppsHook3 — готовит GTK-приложение к запуску в NixOS.
  # patchelf — для добавления DT_RPATH вручную (см. postFixup).
  # zstd — распаковка .pkg.tar.zst.
  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    patchelf
    zstd
  ];

  # Прямые ELF-зависимости (видны через ldd).
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

  # .pkg.tar.zst — tar-архив, сжатый zstd.
  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # AIMP динамически подгружает libcurl.so.4 через dlopen().
    # autoPatchelfHook видит только DT_NEEDED, dlopen-библиотеки — нет.
    # Кладём симлинк рядом с бинарником — некоторые приложения ищут
    # библиотеки в своей директории в первую очередь.
    ln -sf ${curl}/lib/libcurl.so.4 $out/opt/aimp/libcurl.so.4

    # Обёртка на чистом shell. makeWrapper конфликтует с wrapGAppsHook3
    # (тот перезаписывает LD_LIBRARY_PATH), поэтому пишем скрипт сами.
    mkdir -p $out/bin
    cat > $out/bin/aimp <<EOF
#!/bin/sh
# Обёртка AIMP для NixOS. Выставляет LD_LIBRARY_PATH для dlopen-библиотек,
# которые autoPatchelfHook не может пропатчить (libcurl.so.4 и др.).
export LD_LIBRARY_PATH="${lib.makeLibraryPath [ curl openssl ]}"
exec "$out/opt/aimp/AIMP" "\$@"
EOF
    chmod +x $out/bin/aimp

    runHook postInstall
  '';

  postFixup = ''
    # Ключевой фикс: добавляем DT_RPATH (не DT_RUNPATH) в сам бинарник AIMP.
    # Через dlopen из подгруженного .so glibc игнорирует LD_LIBRARY_PATH
    # и смотрит только DT_RPATH. autoPatchelfHook ставит RUNPATH, а нам
    # нужен именно RPATH — поэтому --force-rpath.
    patchelf --force-rpath \
      --add-rpath "${lib.makeLibraryPath [ curl openssl ]}" \
      $out/opt/aimp/AIMP

    # Правим .desktop-файл, чтобы AIMP появился в меню KDE с правильным Exec.
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
