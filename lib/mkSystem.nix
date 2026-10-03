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
# =====================================================================
# Проброс осей устройства (ui, profiles) в диспетчеры.
#
# Диспетчеры ui/default.nix и profiles/default.nix НЕ могут читать
# config.kda.opts: поле `imports` вычисляется до сборки config, и
# ссылка на config вызвала бы infinite recursion (проверено на z13).
# Поэтому mkSystem извлекает оси ПРЯМЫМ вызовом модуля-функции
# devices/<host>/config.nix — он возвращает литеральный attrset, а
# args (config/lib/pkgs) для чтения kda.opts ему не нужны — и
# передаёт их диспетчерам как обычный аргумент `kda` через specialArgs.
# tryEval + дефолт { ui = "none"; } защищают от хостов без осей.
# =====================================================================
let
  # deviceModule — это ПУТЬ к devices/<host>/config.nix (см. flake.nix),
  # поэтому сначала загружаем его через import, и только потом вызываем
  # как функцию модуля. Раньше путь вызывался напрямую → «not a function
  # but a path» при nixos-rebuild на z13.
  deviceModuleFn = import deviceModule;
  # Извлечение осей: модуль устройства вызывается как функция.
  # ВАЖНО: сигнатура devices/<host>/config.nix — { config, lib, pkgs, ... },
  # поэтому ВСЕ объявленные параметры должны быть переданы явно, иначе
  # Nix падает с «called without required argument 'pkgs'» (проверено на z13).
  # Настоящий pkgs НЕ нужен: поле `imports` в конфиге устройства —
  # ЛИТЕРАЛЬНЫЙ список путей, а Nix ленив: выражения из импортируемых
  # модулей (base/tools/*, где используется pkgs.writeShellScriptBin)
  # вычисляются только при реальном включении модуля в систему, чего
  # при «осевом» вызове не происходит. Пустой attrset для pkgs
  # достаточно, чтобы закрыть обязательный параметр функции.
  # tryEval страхует от хостов без объявленных осей (дефолт none/[ ]),
  # но теперь он лишь запасной путь — main-ветка обязана eval-иться чисто.
  hostOpts = builtins.tryEval (
    (deviceModuleFn { config = {}; options = {}; inherit lib inputs; pkgs = { }; }).kda.opts or {}
  );
  axes = if hostOpts.success then hostOpts.value else { };
  kdaAxes = { ui = "none"; profiles = [ ]; } // axes;
in
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  # `kda` — attrset осей, доступен каждому модулю как аргумент функции.
  specialArgs = { inherit inputs; kda = kdaAxes; };
  modules = [
    # Общие модули-инпуты.
    disko.nixosModules.disko
    home-manager.nixosModules.home-manager
    # ВАЖНО: plasma-manager.homeModules.plasma-manager — это HM-модуль
    # (объявляет options.programs.plasma.* внутри Home Manager-домена).
    # Как элемент NixOS `modules` он вызывал «The option `home' does not
    # exist» при eval на z13 — подключается ниже через sharedModules.

    # Конфиг конкретного устройства: сам решает, какие оси включить
    # (kda.opts.ui / kda.opts.profiles + собственные imports).
    deviceModule

    # Диспетчер оси «оконная оболочка»: подключает ui/common + ui/<opts.ui>.
    ../ui/default.nix

    # Диспетчер оси «профили ПО»: подключает llm/, games/, dev/ по opts.profiles.
    ../profiles/default.nix

    # ВАЖНО: lib/options.nix подключается ПОСЛЕДНИМ. В nixpkgs-модулях
    # опции объявляются в фазе option-values, независимо от порядка
    # модулей в списке; а вот *значения* разрешаются в порядке подключения,
    # поэтому `kda.opts = { ... }` из модуля устройства корректно матчится
    # на объявленные здесь опции. Раньше этот модуль стоял ДО устройства —
    # это не влияло на eval, но сбивало с толку при отладке ошибок
    # «The option ... does not exist».
    ../lib/options.nix

    ({ config, ... }:
      let
        username = "lexi";
        hmModules = userHome username;
      in
      {
        _module.args.plasma-manager = plasma-manager;

        home-manager = {
          # Декларативная настройка KDE Plasma (нужна home-модулям ui=="kde").
          # sharedModules подключаются к ДОМЕННОЙ конфигурации Home Manager,
          # где и живут опции programs.plasma.* / home.*.
          sharedModules = [ plasma-manager.homeModules.plasma-manager ];
          useGlobalPkgs = true;
          useUserPackages = true;
          # kdaOpts — оси устройства (ui, profiles), проброшены в home-слой:
          # домашние модули устройств подключают DE-специфичные части
          # через диспетчер devices/<n>/home-specific/default.nix.
          extraSpecialArgs = {
            inherit inputs plasma-manager;
            kdaOpts = config.kda.opts;
          };
        } // lib.optionalAttrs (hmModules != [ ]) {
          users.${username}.imports = hmModules;
        };
      })
  ];
}
