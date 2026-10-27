{ config, lib, pkgs, ... }:

{
  # Команда llm — переключатель режима для LLM-сервисов.
  #   llm local   — сервисы слушают только 127.0.0.1 (по умолчанию)
  #                 + временное правило фаервола сбрасывается
  #   llm global  — сервисы слушают 0.0.0.0 (доступны по LAN)
  #                 + временно открывается TCP-порт 5747 в фаерволе
  #   llm status  — текущий режим + что реально слушает
  #
  # Состояние — файл $HOME/.local/state/llm-mode.env с LLM_HOST=...
  # Файл создаётся лениво при первом вызове. Если файла нет —
  # status показывает 127.0.0.1 (безопасный дефолт).
  #
  # ВАЖНО про фаервол:
  #   NixOS-фаервол (networking.firewall) по умолчанию блокирует
  #   входящие TCP на 5747. Мы НЕ открываем порт декларативно
  #   (allowedTCPPorts), потому что тогда он был бы доступен всегда.
  #   Вместо этого используем nixos-firewall-tool — он добавляет
  #   временное правило в runtime-цепочку nixos-fw, которое:
  #     * не сохраняется между reboot'ами;
  #     * сбрасывается командой `nixos-firewall-tool reset`
  #       (вызывается в `llm local`).
  #
  #   Это значит: после reboot'а режим = local (порт закрыт),
  #   даже если в llm-mode.env осталось LLM_HOST=0.0.0.0.
  #   Если нужно поведение «после reboot'а восстановить режим» —
  #   добавь вызов llm в activation или systemd-юнит, это отдельная
  #   задача.
  #
  #   `nixos-firewall-tool reset` сбрасывает ВСЕ временные правила,
  #   не только для 5747. Если начнёшь открывать через него другие
  #   порты — переделай close_firewall() на точечное удаление.
  #
  # ВАЖНО про Podman:
  #   `-p 5747:5747` без IP публикует порт на 0.0.0.0 — это делает
  #   podman, не мы. Закрытие доступа из LAN обеспечивает фаервол:
  #   пока порт не открыт в nixos-fw, входящие из LAN отбрасываются,
  #   даже если podman слушает 0.0.0.0. Поэтому в local-режиме
  #   podman-порт всё равно будет виден в `podman port` как
  #   0.0.0.0:5747 — это НЕ значит, что он доступен из LAN.
  #
  # ВАЖНО про сервисы:
  #   Команда НЕ перезапускает сервисы. Она только пишет файл
  #   и дёргает фаервол. Чтобы изменения подхватились, сервис надо
  #   перезапустить вручную (strata-stop && strata-start,
  #   systemctl --user restart llama-cpp и т.д.) или он сам должен
  #   читать EnvironmentFile при старте:
  #     EnvironmentFile = "-%h/.local/state/llm-mode.env"
  #     ExecStart = "... --host ''${LLM_HOST} ..."
  environment.systemPackages = [
    # nixos-firewall-tool — обычно уже в системе при включённом
    # networking.firewall, но добавляем явно, чтобы команда llm
    # не зависела от того, что ещё есть в PATH.
    pkgs.nixos-firewall-tool

    (pkgs.writeShellApplication {
      name = "llm";
      runtimeInputs = [
        pkgs.iproute2
        pkgs.coreutils
        pkgs.nixos-firewall-tool
        pkgs.util-linux   # для sudo? нет, sudo отдельно; util-linux для setsid не нужен, но пусть
      ];
      text = ''
        set -euo pipefail

        MODE_FILE="$HOME/.local/state/llm-mode.env"
        PORT="5747"

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

        open_firewall() {
          echo "Открываю TCP-порт $PORT в фаерволе (временно, до reboot'а или llm local)..."
          sudo nixos-firewall-tool open tcp "$PORT"
        }

        close_firewall() {
          echo "Сбрасываю временные правила фаервола..."
          sudo nixos-firewall-tool reset
        }

        case "''${1:-}" in
          local)
            set_mode "127.0.0.1"
            close_firewall
            echo "Сервисы не перезапущены — сделай вручную, когда удобно:"
            echo "  strata-stop && strata-start"
            ;;
          global)
            set_mode "0.0.0.0"
            open_firewall
            echo "Сервисы не перезапущены — сделай вручную, когда удобно:"
            echo "  strata-stop && strata-start"
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
            echo
            echo "Временные правила фаервола:"
            sudo nft list chain inet nixos-fw nixos-fw 2>/dev/null \
              | grep -E "dport $PORT\b" \
              || echo "  (правило для $PORT не найдено — порт закрыт из LAN)"
            ;;
          *)
            echo "Usage: llm {local|global|status}" >&2
            echo "  local  — только 127.0.0.1 + сброс временных правил фаервола" >&2
            echo "  global — 0.0.0.0 + временное открытие TCP $PORT в фаерволе" >&2
            echo "  status — текущий режим и что реально слушает" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];
}
