{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, glibc
, libuv
, zlib
, openssl
, libatomic_ops
, icu
, c-ares
, nghttp2
}:

stdenv.mkDerivation rec {
  pname = "nodejs-official";
  version = "22.23.3";

  # Официальный предсобранный Node.js с nodejs.org.
  # Используется для DeepSeek Harness, потому что нативный аддон
  # node-addon-require-builtin несовместим с Nix-сборкой Node.js.
  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz";
    # Хеш-заглушка: при первой сборке Nix выдаст правильный хеш.
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Не собираем из исходников — используем готовые бинарники.
  dontConfigure = true;
  dontBuild = true;

  # autoPatchelfHook переписывает RPATH бинарников на пути Nix store.
  nativeBuildInputs = [ autoPatchelfHook ];

  # Библиотеки, от которых зависят бинарники Node.js.
  buildInputs = [
    glibc
    libuv
    zlib
    openssl
    libatomic_ops
    icu
    c-ares
    nghttp2
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r * $out/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Official Node.js binary distribution";
    homepage = "https://nodejs.org";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
