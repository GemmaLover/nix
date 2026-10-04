# DeepSeek Harness (DSH) — точка входа.
#
# Локальный вариант (порт 7718):
#   ./local/nix.nix       — константы и пакеты (порт, путь, nodejs-official)
#   ./local/commands.nix  — команды: dsh-local-install/start/stop/...
#
# Контейнерный вариант (порт 7004) — заглушка, пока нет образа:
#   ./container/podman.nix
#   ./container/commands.nix
{ ... }:
{
  imports = [
    ./local/nix.nix
    ./local/commands.nix
    # Раскомментировать, когда появится контейнер DSH:
    # ./container/podman.nix
    # ./container/commands.nix
  ];
}
