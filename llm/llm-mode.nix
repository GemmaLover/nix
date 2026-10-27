{ config, lib, pkgs, ... }:

{
  # Команда llm — переключатель режима для LLM-сервисов.
  #   llm local   — сервисы слушают только 127.0.0.1 (по умолчанию)
  #   llm global  — сервисы слушают 0.0.0.0 (доступны по LAN)
  #   llm status  — текущий режим + что реально слушает
  #
  # Состояние — файл $HOME/.local/state/llm-mode.env с LLM_HOST=...
  # Файл создаётся лениво при первом вызове. Если файла нет —
  # status показывает 127.0.0.1 (безопасный дефолт).
  #
  # Сервисы, которые читают этот файл (llama-cpp, unsloth, dsh),
  # должны иметь EnvironmentFile = "-%h/.local/state/llm-mode.env"
  # и в ExecStart использовать --host ''${LLM_HOST}.
  # Это делается отдельными правками, не в этом файле.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "llm";
      runtimeInputs = [ pkgs.systemd pkgs.iproute2 pkgs.coreutils ];
      text = ''
        set -euo pipefail

        MODE_FILE="$HOME/.local/state/llm-mode.env"

        get_host() {
          if [ -f "$MODE_FILE" ]; then
            # shellcheck disable=SC1090,SC1091
            ( . "$MODE_FILE"; echo "''${LLM_HOST:-127.0.0.1}" )
          else
            echo "127.0.0.1"
          fi
        }

        set_mode() {
          mkdir -p "$(dirname "$MODE_FILE")"
          echo "LLM_HOST=$1" > "$MODE_FILE"
          echo "Режим: LLM_HOST=$1"
        }

        restart_services() {
          # Strata (rootless podman, от имени пользователя).
          if command -v strata-start >/dev/null 2>&1; then
            strata-stop >/dev/null 2>&1 || true
            if strata-start >/dev/null 2>&1; then
              echo "  strata:    перезапущен"
            else
              echo "  strata:    ошибка (см. strata-logs)" >&2
            fi
          fi

          # user-сервисы. Если у тебя они system-level —
          # замени `systemctl --user` на `sudo systemctl`.
          for svc in llama-cpp unsloth dsh; do
            if systemctl --user list-unit-files "$svc.service" >/dev/null 2>&1; then
              if systemctl --user restart "$svc.service" 2>/dev/null; then
                echo "  $svc: перезапущен"
              else
                echo "  $svc: не запущен или ошибка" >&2
              fi
            fi
          done
        }

        case "''${1:-}" in
          local)
            set_mode "127.0.0.1"
            restart_services
            ;;
          global)
            set_mode "0.0.0.0"
            restart_services
            ;;
          status)
            HOST=$(get_host)
            echo "Текущий режим: LLM_HOST=$HOST"
            case "$HOST" in
              127.0.0.1) echo "→ только localhost" ;;
              0.0.0.0)   echo "→ доступны по локальной сети" ;;
              *)         echo "→ неизвестное значение" ;;
            esac
            echo
            echo "Слушают порты:"
            ss -tln 2>/dev/null | grep -E ':(5747|8080|8888)\b' || echo "  (ничего из ожидаемого)"
            ;;
          *)
            echo "Usage: llm {local|global|status}" >&2
            echo "  local  — только 127.0.0.1" >&2
            echo "  global — 0.0.0.0 (доступно по LAN)" >&2
            echo "  status — текущий режим" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];
}
