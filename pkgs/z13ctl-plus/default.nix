{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, glibc
, ryzen_smu ? null  # опциональная зависимость для undervolting
}:

buildGoModule rec {
  pname = "z13ctl-plus";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "aic0d3r";
    repo = "z13ctl-plus";
    rev = "v${version}";
    hash = "sha256-S6dy73wRv9A3d9YkRDYL5LoknW7g2GcMJ+OuaVDpkJ0=";  # заменить после первой сборки
  };

  vendorHash = "sha256-XZjY9g+IaByYca8w1fs+wKarDAeBQEq90c/JBURMIZA=";  # заменить после первой сборки

  # z13ctl-plus использует cgo для доступа к hidraw и sysfs.
  # glibc нужен для работы с системными вызовами.
  buildInputs = [ glibc ];

  nativeBuildInputs = [ pkg-config ];

    # Собираем основной пакет из корня. CLI и демон — это один бинарник
  # z13ctl-plus, который запускается с разными аргументами.
  subPackages = [ "." ];

  # Отключаем проверки, которые требуют доступа к реальному железу.
  doCheck = false;

  meta = with lib; {
    description = "CLI and daemon for ASUS ROG Flow Z13 hardware control";
    homepage = "https://github.com/aic0d3r/z13ctl-plus";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
