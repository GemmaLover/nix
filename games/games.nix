{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # games/games.nix — профиль «games» (ось kda.opts.profiles).
  #
  # Каркас: подключается диспетчером profiles/default.nix, если
  # устройство объявило kda.opts.profiles = [ ... "games" ].
  # Отличия устройств друг от друга — только в наличии llm и games,
  # поэтому весь игровой стек собирается ТОЛЬКО здесь и не попадает
  # в base/ или ui/.
  #
  # TODO(заполнить): Steam / Lutris / GameMode / твики геймпада.
  # Пример наполнения (раскомментировать по мере надобности):
  #   programs.steam.enable = true;         # тянет Proton, runtime
  #   services.gamemoded.enable = true;     # приоритет CPU для игр
  #   hardware.xone.enable = true;          # драйвер Xbox-геймпадов
  # =====================================================================
}
