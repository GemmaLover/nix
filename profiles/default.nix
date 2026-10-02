{ config, lib, ... }:

let
  cfg = config.kda.opts;
in
{
  # =====================================================================
  # profiles/ — ось «необязательные наборы ПО».
  #
  # Диспетчер подключает модули по списку kda.opts.profiles, заданному
  # устройством в devices/<name>/config.nix:
  #   kda.opts.profiles = [ "dev" "llm" ];
  #
  # Сама папка профиля остаётся на месте (llm/, games/, dev/) — здесь
  # только точка подключения. База (сеть, DNS, sing-box, zapret, базовое
  # ПО) в профили НЕ входит: она обязательна для всех устройств и
  # импортируется напрямую из base/.
  #
  # Отличия устройств друг от друга — только в наличии llm и games,
  # поэтому именно эта ось является главным «переключателем» между
  # машинами.
  # =====================================================================

  imports = [ ]
    ++ lib.optionals (lib.elem "dev" cfg.profiles) [ ../dev/dev.nix ]
    ++ lib.optionals (lib.elem "llm" cfg.profiles) [ ../llm/system.nix ]
    ++ lib.optionals (lib.elem "games" cfg.profiles) (
      # games/ пока каркас — подключаем модуль только если файл существует.
      if builtins.pathExists ../games/games.nix then [ ../games/games.nix ] else [ ]
    );
}
