{ config, pkgs, ... }:

{
  # === Home Manager: пользователь lexi ===

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
    userName = "lexi";
    userEmail = "lexi@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
