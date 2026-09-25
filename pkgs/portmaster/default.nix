{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, libnfnetlink
, libnetfilter_queue
, ...
}:

buildGoModule rec {
  pname = "portmaster";
  version = "1.6.18"; # Замените на актуальную версию, если нужно

  src = fetchFromGitHub {
    owner = "safing";
    repo = "portmaster";
    rev = "v${version}";
    hash = "sha256-..."; # Nix выдаст правильный хеш при первой сборке
  };

  vendorHash = "sha256-..."; # Nix выдаст правильный хеш при первой сборке

  # Указываем, какие именно бинарники мы хотим собрать.
  # Основной модуль находится в корне репозитория.
  subPackages = [ "." ];

  # Согласно информации из DeepWiki, сборка Go-бинарников
  # обрабатывается целью +go-build[reference:2].
  # Нам нужно эмулировать это поведение.
  buildPhase = ''
    runHook preBuild
    # Собираем основной бинарник portmaster-start
    go build -v -o portmaster-start ./cmd/start
    # Собираем portmaster-core
    go build -v -o portmaster-core ./cmd/core
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp portmaster-start portmaster-core $out/bin/
    runHook postInstall
  '';

  # Portmaster требует эти библиотеки для работы с сетевым стеком[reference:3].
  buildInputs = [
    libnfnetlink
    libnetfilter_queue
  ];

  nativeBuildInputs = [ pkg-config ];

  meta = with lib; {
    description = "Application firewall that monitors and controls network connections";
    homepage = "https://safing.io/portmaster/";
    license = licenses.gpl3Only;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
