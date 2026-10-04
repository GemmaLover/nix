# DSH в Podman-контейнере (порт 7004) — ЗАГЛУШКА.
#
# Когда появится образ контейнера DSH, описать здесь один из вариантов:
#
# Вариант A — virtualisation.oci-containers (root podman, systemd-сервис):
#   virtualisation.oci-containers.containers.dsh-podman = {
#     image = "docker.io/.../dsh:latest";
#     autoStart = false;
#     ports = [ "127.0.0.1:7004:7718" ];
#     volumes = [ ... ];
#     environment = { ... };
#   };
#
# Вариант B — Quadlet (rootless, systemd --user):
#   home.file.".config/containers/systemd/dsh-podman.container".text = ''
#     [Container]
#     Image=...
#     PublishPort=127.0.0.1:7004:7718
#     ...
#   '';
#
# Команды — в ./commands.nix.
{ ... }:
{
  # Заглушка. Ничего не делаем.
}
