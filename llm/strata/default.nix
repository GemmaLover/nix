{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Strata — движок для Qwen3.8-Flash-Next (125B MoE) на gfx1151.
  #
  # Схема:
  #   - Образ — тонкий Ubuntu 24.04 + тулчейн (cmake/ninja/gcc).
  #     Ubuntu выбран не случайно: TheRock-clang из тарбола динамически
  #     слинкован под FHS (/lib64/ld-linux-x86-64.so.2,
  #     /usr/lib/x86_64-linux-gnu), которых на NixOS нет. Fedora эти
  #     пути тоже не даёт (у неё /usr/lib64), поэтому раньше был
  #     «франкенштейн»: ROCm 10.0 в образе + ROCm 7.14.1 в тарболе.
  #     Здесь ROCm один — 7.14.1 из тарбола.
  #
  #   - ROCm SDK и исходники Strata живут на ХОСТЕ, монтируются в
  #     контейнер read-write. Это удобно: артефакты сборки переживают
  #     перезапуски, а сам ROCm можно потрогать/обновить без пересборки
  #     образа.
  #
  #   - GPU-проброс через --device /dev/kfd --device /dev/dri и
  #     --group-add keep-groups (нужен crun, не runc).
  #
  # Данные на хосте:
  #   ~/llm/strata/
  #   ├── Containerfile        — Nix пишет сюда (symlink в store)
  #   ├── src/                 — git clone Strata
  #   │   ├── build-halo/      — артефакты сборки
  #   │   └── tools/hip/gfx1151-hipblaslt-100401.txt
  #   └── rocm/
  #       ├── therock-dist-linux-gfx1151-7.14.1.tar.gz
  #       └── install/         — распакованный SDK
  #
  # Модель монтируется из ~/llm/models/ (см. модельную переменную ниже).
  # =====================================================================

  # ── Идентификаторы контейнера ────────────────────────────────
  containerName = "strata-server";
  imageName     = "localhost/strata-gfx1151";
  imageTag      = "u24-rocm7141";   # меняй при апдейте Containerfile

  # ── Сеть ─────────────────────────────────────────────────────
  portHost      = 5747;
  portContainer = 5747;

  # ── Каталоги на хосте ────────────────────────────────────────
  home      = config.home.homeDirectory;
  strataDir = "${home}/llm/strata";
  modelsDir = "${home}/llm/models";   # монтируется как /models:ro

  # Путь к модели ОТНОСИТЕЛЬНО modelsDir.
  # Multi-part GGUF: указывается первый файл, остальные подхватятся.
  #
  # Сейчас модель лежит в unsloth-model/. Если в будущем перенесёшь её
  # в ~/llm/models/strata/ud_iq4_xs/, поменяй две строки:
  #   modelsDir = "${home}/llm/models/strata";
  #   modelFile = "ud_iq4_xs/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
  # Симлинк ~/llm/models/strata/ud_iq4_xs → unsloth-model/... НЕ РАБОТАЕТ:
  # symlink резолвится внутри контейнера, где такого пути нет.
  modelFile = "unsloth-model/q3.8fn/ud_iq4_xs/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";

  # ── ROCm TheRock 7.14.1 для gfx1151 ──────────────────────────
  # Хэш из docs/STRIX_HALO.md. Если AMD перезальёт файл — обновить.
  rocmVersion = "7.14.1";
  rocmUrl     = "https://repo.amd.com/rocm/tarball-multi-arch/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz";
  rocmSha256  = "c40e8f2bd6630a7d11557c762b99c6fa8afb04c9bd0e51ed1675ee1ca24afb00";

  # ── Таблица автотюнинга hipBLASLt ────────────────────────────
  # Лежит внутри репозитория Strata. Передаётся через
  # STRATA_HIPBLASLT_TUNING. Версия 100401 = ROCm 7.14.1.
  hipblasltTuning = "tools/hip/gfx1151-hipblaslt-100401.txt";

  # ── Expert cache ─────────────────────────────────────────────
  # Гайд: RAM − 24 GiB − бюджет модели. Для 128 GiB и бюджета ~55 GiB
  # выходит ~49. Ставлю 40 с запасом: auto-режим на 128 ГБ + открытый
  # десктоп ловил глобальный OOM (issue #1715). При недогрузке GPU —
  # увеличивать; при OOM — уменьшать.
  expertCache = 40;

  # ── Быстрый профиль из раздела 5 STRIX_HALO.md ───────────────
  # Включает WMMA-ядра на матричных блоках, fused prompt experts,
  # гипер-связь через Q8 и т.д. Меняет порядок суммирования, поэтому
  # результаты побитово отличаются от дефолтных — но это документированный
  # «maintainers' fast configuration», и он заметно быстрее (см. таблицы
  # в гайде). Дефолты раздела 4 (STRATA_GDN_*, STRATA_HCD_EXACT, ...)
  # движок включает сам на gfx1151 — их руками не выставляем.
  #
  # Для K-квантов (UD-Q4_K_XL, IQ3_S и т.п.) — добавить
  #   "STRATA_PF_FUSED_KQ=1"
  fastEnv = [
    "STRATA_PF_FUSED=1"
    "STRATA_PF_GEMM=1"
    "STRATA_HC_UPMIX=1"
    "STRATA_PA_FAST=1"
    "STRATA_HIP_WMMA=1"
    "STRATA_SELECT_WMMA=1"
    "STRATA_HC_Q8=1"
    "STRATA_PF_SWITCH_MIN_T=4096"
    "STRATA_PREFILL_STREAM_MIN=128"
  ];

  # ── Общие флаги Podman для доступа к GPU ─────────────────────
  # ОДНОЙ СТРОКОЙ, без переносов. Раньше был многострочный литерал
  # с `\` в конце строк — при подстановке в `podman run` последняя
  # строка (`--shm-size=8g`) оставалась без continuation, и shellcheck
  # ругался SC2215: следующая строка (`-v ...`) воспринималась как
  # отдельная команда. Однострочная версия интерполируется безопасно.
  #
  # keep-groups требует crun (в NixOS virtualisation.podman так и есть).
  gpuArgs = "--device /dev/kfd --device /dev/dri --group-add keep-groups --security-opt label=disable --shm-size=8g";

  # То же самое — одной строкой через пробел. Раньше был разделитель
  # " \<newline> " — тоже давал SC2215 в местах подстановки.
  fastEnvArgs = lib.concatMapStringsSep " " (e: "-e ${e}") fastEnv;

  # ── Containerfile (пишется home-manager-ом) ──────────────────
  # Ubuntu 24.04 + минимальный тулчейн. ROCm НЕ внутри — он монтируется.
  # Образ получается ~600 МБ, собирается за 1–2 минуты.
  containerfile = pkgs.writeText "strata.Containerfile" ''
    # FHS-раскладка — обязательна для clang из TheRock.
        FROM docker.io/library/ubuntu:24.04

    ENV DEBIAN_FRONTEND=noninteractive

    # gcc/g++ — хост-тулчейн для clang; libstdc++ берётся из системы.
    # libnuma/libpciaccess/libdrm/libelf — нужны линковщику HIP.
    RUN apt-get update && apt-get install -y --no-install-recommends \
          ca-certificates curl wget git \
          build-essential cmake ninja-build \
          python3 python3-pip pkg-config \
          libnuma-dev libpciaccess-dev libdrm-dev \
          libelf-dev zlib1g-dev libssl-dev \
          clinfo \
        && rm -rf /var/lib/apt/lists/*

    WORKDIR /strata
    CMD ["/bin/bash"]
  '';
in
{
  # Containerfile кладём в ~/llm/strata/Containerfile (symlink в store).
  home.file."llm/strata/Containerfile".source = containerfile;

  # Всё, что нужно скриптам, отдаём через _module.args.strataConfig —
  # commands.nix читает отсюда, хардкода в bash нет.
  _module.args.strataConfig = {
    inherit containerName imageName imageTag
            portHost portContainer
            home strataDir modelsDir modelFile
            rocmVersion rocmUrl rocmSha256
            hipblasltTuning expertCache
            gpuArgs fastEnvArgs;
  };
}
