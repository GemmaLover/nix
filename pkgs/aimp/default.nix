{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook
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
, xorg
, zstd # <-- добавляем zstd для распаковки
}:

stdenv.mkDerivation rec {
  pname = "aimp";
  version = "6.00.3086beta6";

  # Ссылка на .pkg.tar.zst, которую вы предоставили.
  src = fetchurl {
    url = "https://aimp.ru/files/desktop/builds/aimp-6.00.3086beta6-1-x86_64.pkg.tar.zst";
    hash = lib.fakeHash; # Хеш-заглушка
  };

  # Инструменты для сборки.
  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook
    zstd # <-- нужен для распаковки
  ];

  # Зависимости, которые требует AIMP.
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
    xorg.libX11
  ];

  # Явно указываем, как распаковывать .pkg.tar.zst.
  # stdenv не умеет это делать по умолчанию.
  unpackPhase = ''
    tar --use-compress-program=${zstd}/bin/unzstd -xf $src
  '';

  # Устанавливаем файлы из архива в $out.
  # Структура внутри .pkg.tar.zst аналогична другим пакетам: usr/bin, usr/lib и т.д.
  installPhase = ''
    runHook preInstall

    # Копируем всё содержимое архива в $out.
    # Это включает usr/bin/aimp, usr/share/applications, usr/share/icons и т.д.
    cp -r . $out/

    # Создаём симлинк для удобного запуска из командной строки.
    mkdir -p $out/bin
    ln -sf $out/usr/bin/aimp $out/bin/aimp

    runHook postInstall
  '';

  # autoPatchelfHook и wrapGAppsHook обычно работают автоматически.
  # Дополнительные исправления не требуются.

  meta = with lib; {
    description = "AIMP audio player (native Linux version)";
    homepage = "https://aimp.ru";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "aimp";
  };
}
