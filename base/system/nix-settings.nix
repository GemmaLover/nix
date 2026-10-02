# Настройки Nix (общие для всех устройств, слой base/)
# Включает экспериментальные фичи nix-command и flakes на уровне системы,
# чтобы не приходилось каждый раз передавать --extra-experimental-features вручную.
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Автооптимизация store: дедупликация одинаковых путей через hardlinks,
    # чтобы хранилище не разрасталось бесконечно.
    auto-optimise-store = true;
  };

  # Garbage collection раз в неделю (осторожно: оставляет gen-0 и current).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
