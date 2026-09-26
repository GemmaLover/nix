{ config, pkgs, ... }:

{
  # === Home Manager: пользователь lexi ===

  imports = [
    ./home-services.nix
    ./home-caffeine.nix
    ../../llm/home.nix
    ./plasma-power.nix
    ../../base/tools/portmaster-ui.nix
  ];

  # Домашняя директория пользователя.
  home.homeDirectory = "/home/lexi";

  # Имя пользователя (должно совпадать с users.users.lexi).
  home.username = "lexi";

  # stateVersion для Home Manager — НЕ МЕНЯТЬ после первого применения.
  home.stateVersion = "26.05";

  # === Пакеты, установленные только для пользователя ===
  home.packages = with pkgs; [
    # Пользовательские приложения, которые не нужны системе.
  ];

  # === Git ===
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "lexi";
        email = "lexi@example.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
