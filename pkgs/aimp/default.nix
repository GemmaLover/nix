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

  # Официальный пакет AIMP 6 для Linux (Arch Linux .pkg.tar.zst).
  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  # autoPatchelfHook — правит RPATH обычных ELF-зависимостей.
  # wrapGAppsHook3 — готовит GTK-приложение к запуску в NixOS.
  # zstd — распаковка .pkg.tar.zst.
  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
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

    # Обёртка на чистом shell — makeWrapper не работает, потому что
    # wrapGAppsHook3 выполняется позже и перезаписывает LD_LIBRARY_PATH.
    # Явный shell-скрипт выставляет LD_LIBRARY_PATH уже во время
    # запуска, после всех хуков.
    #
    # AIMP подгружает libcurl.so.4 через dlopen() — autoPatchelfHook
    # такие библиотеки не видит. LD_LIBRARY_PATH решает проблему.
    mkdir -p $out/bin
    cat > $out/bin/aimp <<'EOF'
#!/bin/sh
# Обёртка AIMP для NixOS. Выставляет LD_LIBRARY_PATH для dlopen-библиотек,
# которые autoPatchelfHook не может пропатчить (libcurl.so.4 и др.).
EOF

    # Дописываем путь к библиотекам — он должен быть известен на этапе
    # сборки, поэтому выносим за пределы heredoc.
    echo "export LD_LIBRARY_PATH=\"${lib.makeLibraryPath [ curl openssl ]}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\"" >> $out/bin/aimp
    echo "exec \"$out/opt/aimp/AIMP\" \"\$@\"" >> $out/bin/aimp
    chmod +x $out/bin/aimp

    runHook postInstall
  '';

  # Правим .desktop-файл: путь /opt/aimp/AIMP → $out/bin/aimp.
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
