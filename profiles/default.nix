# =====================================================================
# profiles/ — ось «необязательные наборы ПО».
#
# Диспетчер подключает модули по списку opts.profiles, переданному
# хостом через mkSystem (аргумент `kda`, см. lib/mkSystem.nix):
#   kda.opts = { ...; profiles = [ "dev" "llm" ]; };
#
# ВАЖНО: список читается из аргумента `kda`, а НЕ из config.kda.opts —
# imports вычисляются до сборки config, ссылка на config вызвала бы
# infinite recursion (тот же класс ошибки, что и в ui/default.nix).
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
{ kda ? { ui = "none"; profiles = [ ]; }, lib, ... }:

let
  opts = kda;
in
{
  # NOTE: здесь подключаются ТОЛЬКО системные модули профилей.
  # Домашние HM-модули того же профиля (llm/home.nix и т.п.) живут в
  # home-слое устройства (devices/<host>/home.nix) — их нельзя импортировать
  # сюда: опция `home.*` существует только в Home Manager, а не в NixOS
  # (иначе eval падает с «The option `home' does not exist»).
  imports = [ ]
    ++ lib.optionals (lib.elem "dev" opts.profiles) [ ../dev/dev.nix ]
    ++ lib.optionals (lib.elem "llm" opts.profiles) [ ../llm/system.nix ]
    # games/ пока каркас — подключаем модуль только если файл существует.
    ++ lib.optionals (lib.elem "games" opts.profiles)
      (if builtins.pathExists ../games/games.nix then [ ../games/games.nix ] else [ ]);
}
