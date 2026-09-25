{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, qt6
, libxcb
, xcb-util-cursor
, libxkbcommon
, libGL
, libxcb-icccm
, libxcb-image
, libxcb-keysyms
, libxcb-render-util
, libxcb-xinerama
, libxcb-util
, libxcb-xkb
, libxcb-cursor
, libpulseaudio
, alsa-lib
, libsecret
, p7zip
, makeWrapper
}:

stdenv.mkDerivation rec {
  pname = "amnezia-vpn-run";
  version = "5.0.3.0";

  # Скачиваем .run файл напрямую с GitHub.
  src = fetchurl {
    url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/${version}/AmneziaVPN_${version}_linux_x64.run";
    # Хэш нужно будет получить после первой попытки сборки.
    # Замените "sha256-..." на правильное значение.
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # .run файл не является стандартным архивом, поэтому распаковываем его вручную.
  dontUnpack = true;

  # Инструменты, необходимые для сборки и патчинга.
  nativeBuildInputs = [
    autoPatchelfHook
    qt6.wrapQtAppsHook
    makeWrapper
    p7zip
  ];

  # Библиотеки, которые нужны приложению.
  buildInputs = [
    qt6.qtbase
    qt6.qtwayland
    qt6.qt5compat
    libxcb
    xcb-util-cursor
    libxkbcommon
    libGL
    libxcb-icccm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-xinerama
    libxcb-util
    libxcb-xkb
    libxcb-cursor
    libpulseaudio
    alsa-lib
    libsecret
  ];

  # Указываем autoPatchelfHook игнорировать некоторые "недостающие" зависимости,
  # которые на самом деле являются частью самого приложения.
  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall

    # Создаём временную директорию для распаковки.
    mkdir -p $TMPDIR/amnezia_extract
    cd $TMPDIR/amnezia_extract

    # Делаем .run файл исполняемым и запускаем его в "тихом" режиме.
    # Флаг --target указывает, куда распаковывать содержимое.
    # Флаг --noexec предотвращает запуск скриптов установки, мы просто хотим извлечь файлы.
    chmod +x $src
    $src --target $TMPDIR/amnezia_extract --noexec

    # После распаковки обычно появляется директория с бинарниками.
    # Ищем исполняемый файл AmneziaVPN.
    # Путь может отличаться в зависимости от версии.
    # Предположим, что он находится в ./bin/AmneziaVPN или ./AmneziaVPN.
    # Найдём его.
    AMNEZIA_BIN=$(find . -name "AmneziaVPN" -type f | head -n 1)

    if [ -z "$AMNEZIA_BIN" ]; then
      echo "Не удалось найти исполняемый файл AmneziaVPN после распаковки."
      exit 1
    fi

    # Копируем все распакованные файлы в $out.
    mkdir -p $out
    cp -r ./* $out/

    # Создаём обёртку для запуска, чтобы установить необходимые переменные окружения.
    # Это особенно важно для Qt-приложений.
    mkdir -p $out/bin
    makeWrapper "$out/bin/AmneziaVPN" "$out/bin/amnezia-vpn" \
      --prefix LD_LIBRARY_PATH : "$out/lib" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtbase}/lib/qt-6/plugins"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Amnezia VPN client (official binary release)";
    homepage = "https://github.com/amnezia-vpn/amnezia-client";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "amnezia-vpn";
  };
}
