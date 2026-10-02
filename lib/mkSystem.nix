{
  inputs,
  nixpkgs,
  home-manager,
  disko,
  plasma-manager,
}:
let lib = nixpkgs.lib; in
# =====================================================================
# mkSystem — фабрика ноды flake.nixosConfigurations для устройства.
#
# Убирает из flake.nix ручное перечисление модулей home-manager и
# plasma-manager: достаточно указать deviceModule (devices/<n>/config.nix).
#
# userHome — функция (имя пользователя => список home-модулей), либо null.
# Home Manager включается только если для пользователя есть модули —
# это позволяет headless-устройствам не тянуть HM-конфиг.
#
# Модуль plasma-manager подключается ЗДЕСЬ (homeModules), а не во
# flake.nix — так же, как disko и home-manager.
# =====================================================================
deviceName:
{ deviceModule, userHome ? (user: [ ]) }:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    # Общие модули-инпуты.
    disko.nixosModules.disko
    home-manager.nixosModules.home-manager
    # Декларативная настройка KDE Plasma (нужна home-модулям ui=="kde").
    plasma-manager.homeModules.plasma-manager

    # Кастомные опции kda.opts (ui, profiles) доступны всем модулям.
    ../lib/options.nix

    # Диспетчер оси «оконная оболочка»: подключает ui/common + ui/<opts.ui>.
    ../ui/default.nix

    # Диспетчер оси «профили ПО»: подключает llm/, games/, dev/ по kda.opts.profiles.
    ../profiles/default.nix

    # Конфиг конкретного устройства: сам решает, какие оси включить
    # (kda.opts.ui / kda.opts.profiles + собственные imports).
    deviceModule

    ({ config, ... }:
      let
        username = "lexi";
        hmModules = userHome username;
      in
      {
        _module.args.plasma-manager = plasma-manager;

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          # kdaOpts — оси устройства (ui, profiles), проброшены в home-слой:
          # домашние модули устройств подключают DE-специфичные части
          # через диспетчер devices/<n>/home-specific/default.nix.
          extraSpecialArgs = {
            inherit inputs plasma-manager;
            kdaOpts = config.kda.opts or { ui = "none"; profiles = [ ]; };
          };
        } // lib.optionalAttrs (hmModules != [ ]) {
          users.${username}.imports = hmModules;
        };
      })
  ];
}
