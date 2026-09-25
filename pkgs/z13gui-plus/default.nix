{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, gtk4
, libadwaita
, gobject-introspection
, wrapGAppsHook4
, gtk4-layer-shell
}:

buildGoModule rec {
  pname = "z13gui-plus";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "aic0d3r";
    repo = "z13gui-plus";
    rev = "v${version}";
    hash = "sha256-VOd3eD9l6n0hj/gTFo8K1QRMT3rL0kqWG1NV1fxQlAc=";  # заменить
  };

  vendorHash = "sha256-7XEC7eAeVnJTdHoGa99zAkf2Yk7JkjLy2HML4UthOLo=";  # заменить

  # z13gui-plus — GTK4-оверлей, требует GTK4 и libadwaita.
  buildInputs = [
    gtk4
    libadwaita
    gtk4-layer-shell
  ];

  nativeBuildInputs = [
    pkg-config
    gobject-introspection
    wrapGAppsHook4
  ];

  # GUI-приложение, не требует проверок.
  doCheck = false;

  meta = with lib; {
    description = "GTK4 overlay companion for z13ctl";
    homepage = "https://github.com/aic0d3r/z13gui-plus";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
