{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Strata — движок Qwen3.8-Flash-Next (125B MoE) на gfx1151.
  #
  # Архитектура проекта:
  #   1. strata (наш build-halo/strata) — низкоуровневый движок, работает
  #      с PACK-каталогом (не GGUF), общается с сервером через stdio.
  #   2. serve/server.py — HTTP-сервер (OpenAI- и Anthropic-совместимый).
  #      Спавнит strata --serve как subprocess.
  #   3. setup.py — оркестратор: определяет GPU, качает модель с HF,
  #      строит pack, пишет конфиг, ставит Python-зависимости в .venv,
  #      при необходимости собирает движок, и запускает serve/server.py.
  #
  # Схема запуска:
  #   первый раз  → python setup.py --setup [интерактивные вопросы] --no-start
  #   каждый раз  → python setup.py --port N
  #
  # Пересборка движка: setup.py смотрит на engine/BUILD.json. Если
  # backend=hip, src совпадает с source_hash(ENGINE_SOURCES) и archs
  # содержит gfx1151 — компиляцию пропустит. Мы генерим BUILD.json в
  # strata-setup, поэтому setup.py использует уже собранный build-halo.
  #
  # ПОЧЕМУ UBUNTU: TheRock-clang слинкован под FHS
  # (/lib64/ld-linux-x86-64.so.2, /usr/lib/x86_64-linux-gnu), которых
  # на NixOS нет. Плюс setup.py требует python3-venv и стандартную
  # FHS-раскладку для pip и venv.
  #
  # Каталоги на хосте:
  #   ~/llm/strata/
  #   ├── Containerfile        — symlink в store
  #   ├── src/                 — git clone Strata
  #   │   ├── .venv/           — Python venv (numpy, jinja2, ...)
  #   │   ├── build-halo/      — скомпилированный движок
  #   │   ├── engine/          — setup.py ждёт бинарь здесь
  #   │   └── tools/hip/gfx1151-hipblaslt-100401.txt
  #   ├── rocm/
  #   │   └── install/         — распакованный TheRock (монтируется как /opt/rocm)
  #   └── data/                — volume /data: pack, конфиг, MTP, HOME
  #
  #   ~/llm/models/strata/     — volume /models: GGUF-модели (setup.py
  #                              качает сюда через --models-dir /models)
  # =====================================================================

  # ── Контейнер ────────────────────────────────────────────────
  containerName = "strata-server";
  imageName     = "localhost/strata-gfx1151";
  imageTag      = "u24-rocm7141-v3";   # v3: интерактивный setup, --models-dir

  # ── Сеть ─────────────────────────────────────────────────────
  portHost      = 5747;
  portContainer = 5747;

  # ── Каталоги на хосте ────────────────────────────────────────
  home      = config.home.homeDirectory;
  strataDir = "${home}/llm/strata";
  dataDir   = "${strataDir}/data";              # pack, конфиг, MTP, HOME
  modelsDir = "${home}/llm/models/strata";      # GGUF-модели

  # ── ROCm TheRock 7.14.1 (нужен для сборки движка) ────────────
  rocmVersion = "7.14.1";
  rocmUrl     = "https://repo.amd.com/rocm/tarball-multi-arch/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz";
  rocmSha256  = "c40e8f2bd6630a7d11557c762b99c6fa8afb04c9bd0e51ed1675ee1ca24afb00";

  # ── Флаги Podman для GPU ─────────────────────────────────────
  # ОДНОЙ СТРОКОЙ — многострочный литерал с `\` ломает shellcheck
  # (SC2215) при подстановке в podman run.
  gpuArgs = "--device /dev/kfd --device /dev/dri --group-add keep-groups --security-opt label=disable --shm-size=8g";

  # ── Containerfile ────────────────────────────────────────────
  # Ubuntu 24.04 + Python3 (3.12) + venv + тулчейн.
  # ROCm НЕ внутри — монтируется /opt/rocm с хоста.
  containerfile = pkgs.writeText "strata.Containerfile" ''
    # FHS-раскладка — обязательна для clang из TheRock и для venv.
    # Полное имя: podman rootless не резолвит short-name без
    # unqualified-search-registries в /etc/containers/registries.conf.
    FROM docker.io/library/ubuntu:24.04

    ENV DEBIAN_FRONTEND=noninteractive
    ENV PYTHONUNBUFFERED=1
    ENV LANG=C.UTF-8

    # python3-venv — для pip install requirements.txt.
    # Тулчейн (build-essential/cmake/ninja) — если setup.py решит
    # всё-таки собирать движок сам (мы этого избегаем через
    # engine/BUILD.json, но пусть будет).
    # libnuma/libpciaccess/libdrm/libelf/libatomic/libgomp —
    # нужны линковщику HIP и рантайму движка.
    RUN apt-get update && apt-get install -y --no-install-recommends \
          build-essential ca-certificates curl wget git \
          cmake ninja-build pkg-config unzip file \
          python3 python3-pip python3-venv \
          libnuma-dev libpciaccess-dev libdrm-dev libelf-dev \
          zlib1g-dev libssl-dev libatomic1 libgomp1 \
          clinfo \
        && rm -rf /var/lib/apt/lists/*

    WORKDIR /strata
    CMD ["/bin/bash"]
  '';
in
{
  # Containerfile в ~/llm/strata/Containerfile (symlink в store).
  home.file."llm/strata/Containerfile".source = containerfile;

  # Всё, что нужно скриптам, отдаём через _module.args.strataConfig.
  _module.args.strataConfig = {
    inherit containerName imageName imageTag
            portHost portContainer
            home strataDir dataDir modelsDir
            rocmVersion rocmUrl rocmSha256
            gpuArgs;
  };
}
