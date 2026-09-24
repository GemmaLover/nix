{ config, pkgs, ... }:

{
  # === Home Manager: пользователь lexi ===

  # Домашняя директория.
  home.homeDirectory = "/home/lexi";

  # Имя пользователя (должно совпадать с users.users.lexi).
  home.username = "lexi";

  # stateVersion для Home Manager — НЕ МЕНЯТЬ после первого применения.
  home.stateVersion = "26.05";

  # === Пакеты, установленные только для пользователя ===
  home.packages = with pkgs; [
    # Пользовательские приложения, которые не нужны системе.
    # Например, персональные утилиты, игры и т.д.
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

  # === Firefox ===
  # Home Manager может управлять настройками Firefox декларативно.
  # Это удобно для синхронизации настроек между устройствами.
  # programs.firefox = {
  #   enable = true;
  #   profiles.default = {
  #     settings = {
  #       "browser.startup.homepage" = "https://nixos.org";
  #     };
  #   };
  # };

  # === KDE ===
  # KDE Plasma настраивается через system-level (base/ui/kde.nix).
  # Home Manager может дополнять пользовательские настройки.
  # Например, горячие клавиши, темы и т.д.
}{ config, pkgs, ... }:

{
  # === Home Manager: пользователь lexi ===

  # Домашняя директория.
  home.homeDirectory = "/home/lexi";

  # Имя пользователя (должно совпадать с users.users.lexi).
  home.username = "lexi";

  # stateVersion для Home Manager — НЕ МЕНЯТЬ после первого применения.
  home.stateVersion = "26.05";

  # === Пакеты, установленные только для пользователя ===
  home.packages = with pkgs; [
    # Пользовательские приложения, которые не нужны системе.
    # Например, персональные утилиты, игры и т.д.
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

  # === Firefox ===
  # Home Manager может управлять настройками Firefox декларативно.
  # Это удобно для синхронизации настроек между устройствами.
  # programs.firefox = {
  #   enable = true;
  #   profiles.default = {
  #     settings = {
  #       "browser.startup.homepage" = "https://nixos.org";
  #     };
  #   };
  # };

  # === KDE ===
  # KDE Plasma настраивается через system-level (base/ui/kde.nix).
  # Home Manager может дополнять пользовательские настройки.
  # Например, горячие клавиши, темы и т.д.
}
