{ config, pkgs, lib, ... }:

let
  # =====================================================================
  # Strata — движок для Qwen3.8-Flash-Next (125B MoE).
  #
  # Работает на AMD Strix Halo (gfx1151) через HIP/ROCm.
  # Готового Docker-образа для AMD нет. Сборка из исходников по
  # инструкции docs/STRIX_HALO.md:
  #   1. Скачивается ROCm SDK 7.14.1 для gfx1151 с repo.amd.com
  #      (therock-dist-linux-gfx1151-7.14.1.tar.gz, ~1.7 ГБ).
  #   2. Движок собирается через CMake+Ninja в контейнере Fedora
  #      (kyuz0/amd-strix-halo-toolboxes) с ROCm-clang из SDK.
  #      На хосте не собираем: clang из therock-dist динамически
  #      слинкован под FHS, на NixOS не запустится.
  #
  # Где живут данные (всё на хосте, монтируется в контейнер):
  #   ~/llm/strata/                — корень
  #   ~/llm/strata/.git/           — исходники Strata (git clone)
  #   ~/llm/strata/build-halo/     — скомпилированный движок
  #   ~/llm/strata/rocm/           — ROCm SDK (tar.gz + install/)
  #   ~/llm/strata/models/         — GGUF-модели (по желанию)
  #
  # Порт: 5747.
  # =====================================================================

  image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0_20261010T195700";

  portHost = 5747;
  portContainer = 5747;

  strataDir = "${config.home.homeDirectory}/llm/strata";

  # ROCm SDK для gfx1151 (TheRock, multi-arch tarball).
  # ВАЖНО: хэш сверяется при скачивании. Если AMD обновит файл,
  # проверка упадёт — обнови rocmSha256 вручную.
  rocmVersion = "7.14.1";
  rocmUrl = "https://repo.amd.com/rocm/tarball-multi-arch/therock-dist-linux-gfx1151-${rocmVersion}.tar.gz";
  rocmSha256 = "c40e8f2bd6630a7d11557c762b99c6fa8afb04c9bd0e51ed1675ee1ca24afb00";

  # Таблица автотюнинга hipBLASLt для gfx1151.
  # Лежит в самом репозитории Strata: tools/hip/gfx1151-hipblaslt-100401.txt.
  # Передаётся движку через STRATA_HIPBLASLT_TUNING.
  hipblasltTuning = "tools/hip/gfx1151-hipblaslt-100401.txt";
in
{
  _module.args.strataConfig = {
    inherit image portHost portContainer strataDir
            rocmVersion rocmUrl rocmSha256 hipblasltTuning;
  };
}
