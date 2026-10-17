{ config, lib, ... }:

let
  cfg = config.kda;
in
{
  # =====================================================================
  # Кастомные опции NixOS слоя «kda».
  #
  # Идея: конфигурация собирается из четырёх ортогональных осей:
  #   1. base/            — база для всех устройств (сеть, DNS, sing-box,
  #                         zapret, базовое ПО). Не зависит от DE и железа.
  #   2. opts.ui          — оконная оболочка (kde | hyprland | niri). Один
  #                         из вариантов подключается через ui/default.nix.
  #   3. devices/<name>/  — железо: ядро, udev-правила, драйверы,
  #                         vendor-специфичные утилиты.
  #   4. opts.profiles    — необязательные наборы ПО: llm, games, dev.
  #                         Отличия устройств — только в наличии llm/games.
  #
  # Устройство описывает свои оси в devices/<name>/config.nix:
  #   kda.opts = { ui = "niri"; profiles = [ "llm" ]; };
  # =====================================================================
  options.kda.opts = with lib; {

    ui = mkOption {
      # === ИЗМЕНЕНО: добавлен "niri" (Wayland-композитор + Noctalia) ===
      type = types.enum [ "none" "kde" "hyprland" "niri" ];
      default = "none";
      description = ''
        Оконная оболочка устройства.
          "kde"      — Plasma 6 + SDDM (ui/kde/).
          "hyprland" — Wayland-композитор Hyprland (ui/hyprland/, каркас).
          "niri"     — Wayland-композитор Niri + Noctalia (ui/niri/).
          "none"     — headless / без графической оболочки.
      '';
    };

    profiles = mkOption {
      type = types.listOf (types.enum [ "dev" "llm" "games" ]);
      default = [ ];
      description = ''
        Необязательные профили ПО, подключаемые к устройству.
        Базовые модули (network, dns, sing-box, zapret, tools) входят
        в состав ВСЕХ устройств и здесь не перечисляются.
      '';
    };
  };
}
