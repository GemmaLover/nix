# =====================================================================
# lib/ — вспомогательные функции сборки конфигурации.
#
# mkSystem.nix  — фабрика nixosSystem: принимает имя устройства,
#                 path к его config.nix и inputs; сам подставляет
#                 home-manager, plasma-manager и disko.
# options.nix   — кастомные опции kda.opts (ui, profiles).
# =====================================================================
{
  mkSystem = import ./mkSystem.nix;
}
