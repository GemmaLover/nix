{ lib
, stdenv
, fetchFromGitHub
, bash
, coreutils
, procps
, udev
}:

stdenv.mkDerivation rec {
  pname = "z13-tablet-kit";
  version = "unstable-2026-08-05";

    buildInputs = [ coreutils ];


  src = fetchFromGitHub {
    owner = "aic0d3r";
    repo = "z13-tablet-kit";
    rev = "master";
    hash = "sha256-zBaen/P7+9uf5X0UB3ClE+MdonB24HlvSAOfuVOG6kk=";  # заменить
  };

  # z13-tablet-kit — набор shell-скриптов, а не бинарник.
  # Не собираем, а устанавливаем.
  dontBuild = true;


  # Заменяем жёстко прописанные FHS-пути (/usr/bin/...) на пути из Nix store.
  # Это стандартная практика для udev-правил в NixOS.
  # /usr/bin/chmod -> /nix/store/...-coreutils-.../bin/chmod
  # /usr/bin/chgrp -> /nix/store/...-coreutils-.../bin/chgrp
  postPatch = ''
    substituteInPlace udev/99-disable-asus-touchpad.rules \
      --replace "/usr/bin/chmod" "${coreutils}/bin/chmod" \
      --replace "/usr/bin/chgrp" "${coreutils}/bin/chgrp"
  '';

  installPhase = ''
    runHook preInstall

    # Устанавливаем скрипты в bin.
    mkdir -p $out/bin
    for script in z13-tablet-switch z13-touch-scroll dock; do
      if [ -f "$script" ]; then
        install -Dm755 "$script" "$out/bin/$script"
      fi
    done

    # Устанавливаем udev-правила.
    if [ -d "udev" ]; then
      mkdir -p $out/lib/udev/rules.d
      cp udev/*.rules $out/lib/udev/rules.d/ 2>/dev/null || true
    fi

    # Устанавливаем systemd-юниты, если они есть в репозитории.
    if [ -d "systemd" ]; then
      mkdir -p $out/lib/systemd/user
      cp systemd/*.service $out/lib/systemd/user/ 2>/dev/null || true
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "ASUS Z13 tablet mode toolkit";
    homepage = "https://github.com/aic0d3r/z13-tablet-kit";
    license = licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
