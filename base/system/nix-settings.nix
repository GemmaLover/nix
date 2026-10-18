# Настройки Nix (общие для всех устройств, слой base/)
# Включает экспериментальные фичи nix-command и flakes на уровне системы,
# чтобы не приходилось каждый раз передавать --extra-experimental-features вручную.
#
# ВАЖНО: файл должен принимать аргументы { config, lib, pkgs, ... },
# потому что ниже используется lib.mkForce — без lib в аргументах
# nix flake check упадёт с «undefined variable 'lib'».
{ config, lib, pkgs, ... }:
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Автооптимизация store: дедупликация одинаковых путей через hardlinks,
    # чтобы хранилище не разрасталось бесконечно.
    auto-optimise-store = true;

    # === НОВОЕ: игнорировать nixConfig из flake-файлов ===
    # Запрещает Nix автоматически применять настройки кэшей из flake-файлов
    # при их вычислении. Без этого niri-flake и noctalia добавляют свои
    # extra-substituters, и Nix висит по 300 секунд на каждой попытке
    # скачать narinfo с недоступного из РФ niri.cachix.org.
    accept-flake-config = false;

    # === НОВОЕ: принудительно фиксируем substituters ===
    # NixOS-модуль niri-flake выставляет
    #   nix.settings.extra-substituters = [ "https://niri.cachix.org" ],
    # который ДОБАВЛЯЕТСЯ к нашему substituters и НЕ отключается через
    # accept-flake-config (это разные механизмы: accept-flake-config
    # управляет чтением nixConfig из flake-файлов, а extra-substituters —
    # обычная опция nix.settings, которую выставляет NixOS-модуль).
    #
    # mkForce на substituters и явная очистка extra-substituters
    # убирают niri.cachix.org из итогового /etc/nix/nix.conf.
    # Без этого в nix.conf остаётся:
    #   substituters = https://niri.cachix.org https://cache.nixos.org/ https://cache.nixos.org/
    # и n13rebuild зависает на flake check.
    substituters = lib.mkForce [ "https://cache.nixos.org/" ];
    extra-substituters = lib.mkForce [ ];

    # То же самое для trusted-public-keys: niri-flake добавляет
    # свой ключ через extra-trusted-public-keys, который тянет
    # за собой подпись для niri.cachix.org. Очищаем.
    trusted-public-keys = lib.mkForce [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    extra-trusted-public-keys = lib.mkForce [ ];

    # Таймаут и fallback на случай проблем с сетью:
    #   connect-timeout = 5 — если кэш не отвечает за 5 секунд,
    #     Nix идёт к следующему, а не ждёт дефолтные 300 секунд;
    #   fallback = true — если пакета нет в кэше, собирать локально,
    #     а не падать с «cannot find».
    connect-timeout = 5;
    fallback = true;
  };

  # Garbage collection раз в неделю (осторожно: оставляет gen-0 и current).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
