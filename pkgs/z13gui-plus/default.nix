{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, gtk4
, libadwaita
, gobject-introspection
, wrapGAppsHook4
}:

buildGoModule rec {
  pname = "z13gui-plus";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "aic0d3r";
    repo = "z13gui-plus";
    rev = "v${version}";
    hash = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";  # заменить
  };

  vendorHash = "sha256-DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=";  # заменить

  # z13gui-plus — GTK4-оверлей, требует GTK4 и libadwaita.
  buildInputs = [
    gtk4
    libadwaita
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
