# =====================================================================
# ui/niri/ — ось «Niri + Noctalia».
# Подключается при kda.opts.ui = "niri" (см. ui/default.nix).
#
# Содержит системный слой Niri (niri.nix). Пользовательская настройка
# (биндинги, layout, Noctalia) — в home.nix, подключается диспетчером
# devices/<host>/home-specific/default.nix.
# =====================================================================
{ config, lib, pkgs, ... }:

{
  imports = [
    ./niri.nix
  ];
}
