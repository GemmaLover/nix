{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, libnfnetlink
, libnetfilter_queue
}:

buildGoModule rec {
  pname = "portmaster";
  version = "1.6.18";

  src = fetchFromGitHub {
    owner = "safing";
    repo = "portmaster";
    rev = "v${version}";
    # fakeHash — это специальная константа Nix (все нули в base32),
    # которая гарантированно не совпадёт с реальным хэшем.
    # При первой сборке Nix выдаст правильное значение в ошибке.
        hash = "sha256-K/HEDVWgjW//m+CqIiL+xgKRObNMOtjY1Z8myTkDXSw=";
  };

  # То же самое для vendorHash — хэша Go-зависимостей.
    vendorHash = "sha256-/sxjCSPhsZZwQv7w1bKiBoBnS7jozJIbyu8S64TOe4Q=";

  # ... остальное содержимое файла без изменений
}
