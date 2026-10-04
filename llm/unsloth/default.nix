# Константы для контейнера Unsloth.
#
# Вынесены отдельно, чтобы commands.nix не дублировал пути и порты.
# Через _module.args.unslothConfig доступны как аргумент модуля.
{ config, pkgs, lib, ... }:

let
  # Образ Unsloth для AMD (ROCm). Тег studio включает веб-UI.
  # Актуальные теги: latest, nightly, gfx1151 (для Strix Halo) — см.
  # https://hub.docker.com/r/unsloth/unsloth-rocm
  image = "docker.io/unsloth/unsloth-rocm:studio";

  # Внешний порт (на хосте) и внутренний (в контейнере).
  # Unsloth Studio слушает 8000 внутри. Наружу пробрасываем 8005,
  # чтобы не конфликтовать с другими сервисами.
  portHost = 8005;
  portContainer = 8000;

  # Имя volume для состояния Studio (аккаунты, чаты, настройки).
  dataVolume = "unsloth-data";

  # Папка с проектами хоста, монтируется в /workspace/host.
  hostProjects = "${config.home.homeDirectory}/projects";

  # Кэш моделей HuggingFace. Монтируется в /workspace/.cache/huggingface,
  # потому что HF_HOME внутри образа указывает именно туда.
  # Без этого монтирования модели исчезают после podman rm.
  hfCache = "${config.home.homeDirectory}/llm/models";
in
{
  _module.args.unslothConfig = {
    inherit image portHost portContainer dataVolume hostProjects hfCache;
  };
}
