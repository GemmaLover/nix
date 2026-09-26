{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3          # было wrapGAppsHook
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
, libx11                  # было xorg.libX11
, zstd
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
    wrapGAppsHook3        # здесь тоже
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
    libx11                # и здесь
  ];

  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    # Копируем корневые директории из архива: opt, usr (если есть).
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # Создаём симлинк на реальный бинарник в opt/aimp.
    # В .pkg.tar.zst от AIMP он лежит в /opt/aimp/AIMP.
    mkdir -p $out/bin
    if [ -x $out/opt/aimp/AIMP ]; then
      ln -s $out/opt/aimp/AIMP $out/bin/aimp
    elif [ -x $out/opt/aimp/aimp ]; then
      ln -s $out/opt/aimp/aimp $out/bin/aimp
    else
      echo "Не найден бинарник AIMP в opt/aimp/"
      ls -la $out/opt/aimp/ || true
      exit 1
    fi

    runHook postInstall
  '';

  # Правим .desktop, если он есть в архиве: путь к бинарнику.
  postFixup = ''
    if [ -f $out/share/applications/aimp.desktop ]; then
      substituteInPlace $out/share/applications/aimp.desktop \
        --replace "/opt/aimp/AIMP" "$out/bin/aimp" \
        --replace "/usr/bin/aimp" "$out/bin/aimp" || true
    fi
  '';

  meta = with lib; {
    description = "AIMP audio player (native Linux version)";
    homepage = "https://aimp.ru";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "aimp";
  };
}
