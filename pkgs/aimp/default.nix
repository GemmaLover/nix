{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeWrapper
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
  # Ссылка ведёт на конкретную бета-сборку, ID может измениться
  # при выходе новой версии — тогда обновить url и hash.
  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = "sha256-K/Yb/I1HIqlkh08zCoWqMDr61iLpgxiGr7lm5lAmd3c=";
  };

  # Инструменты сборки:
  # - autoPatchelfHook: правит RPATH обычных ELF-зависимостей.
  # - wrapGAppsHook3: подготавливает GTK-приложение к запуску в NixOS.
  # - makeWrapper: создаёт обёртку с LD_LIBRARY_PATH для dlopen-библиотек.
  # - zstd: распаковка .pkg.tar.zst (stdenv не умеет по умолчанию).
  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
    zstd
  ];

  # Библиотеки, которые AIMP линкует напрямую (видны через ldd).
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

  # .pkg.tar.zst — это tar-архив, сжатый zstd.
  # stdenv не умеет его распаковывать сам, делаем вручную.
  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    # Внутри архива: opt/aimp (сам плеер), usr/ (иконки, .desktop).
    cp -r opt $out/
    [ -d usr ] && cp -r usr $out/ || true

    # Обёртка вокруг AIMP с LD_LIBRARY_PATH.
    # AIMP динамически подгружает libcurl.so.4 через dlopen(),
    # autoPatchelfHook такие зависимости не видит. LD_LIBRARY_PATH
    # указывает линкеру, где искать .so при запуске.
    mkdir -p $out/bin
    makeWrapper $out/opt/aimp/AIMP $out/bin/aimp \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ curl openssl ]}"

    runHook postInstall
  '';

  # Правим .desktop-файл: путь /opt/aimp/AIMP → $out/bin/aimp.
  # В Arch-пакете .desktop ссылается на абсолютный путь, в NixOS
  # его нужно переписать на store-путь.
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
