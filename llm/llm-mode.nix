{ config, lib, pkgs, ... }:

let
  # Порты активных LLM-сервисов (host-сторона).
  # Источники:
  #   strata       — llm/strata/default.nix:52   (portHost)
  #   dsh (local)  — llm/dsh/local/nix.nix:22    (port)
  #   unsloth      — llm/unsloth/default.nix:16  (portHost)
  #   cockpit ROCm — llm/cockpit/default.nix:31  (portHost)
  #   cockpit Vulk — llm/cockpit/default.nix:38  (portHost)
  #   gufo         — llm/gufo/default.nix:25     (portHost)
  #
  # deprecated/* не включены: не импортируются в llm/home.nix.
  # Если добавишь новый сервис — допиши его порт сюда.
  llmPorts = [ 5747 7718 8005 8085 8086 8640 ];

  portsStr = builtins.concatStringsSep " " (map toString llmPorts);
  portsRe  = builtins.concatStringsSep "|" (map toString llmPorts);
in
{
  # Команда llm — переключатель режима для LLM-сервисов.
  #   llm local   — сервисы слушают только 127.0.0.1 (по умолчанию)
  #                 + временные правила фаервола сбрасываются
  #   llm global  — сервисы слушают 0.0.0.0 (доступны по LAN)
  #                 + временно открываются TCP-порты LLM в фаерволе
  #   llm status  — текущий режим, что слушает, что открыто в фаерволе
  #
  # Состояние — файл $HOME/.local/state/llm-mode.env с LLM_HOST=...
  # Файл создаётся лениво при первом вызове. Если файла нет —
  # status показывает 127.0.0.1 (безопасный дефолт).
  #
  # ВАЖНО про фаервол:
  #   NixOS-фаервол (networking.firewall) по умолчанию блокирует
  #   входящие TCP на порты LLM. Мы НЕ открываем их декларативно
  #   (allowedTCPPorts), потому что тогда они были бы доступны всегда.
  #   Вместо этого используем nixos-firewall-tool — он добавляет
  #   временные правила, которые:
  #     * не сохраняются между reboot'ами;
  #     * сбрасываются командой `nixos-firewall-tool reset`
  #       (вызывается в `llm local`).
  #   Это значит: после reboot'а режим = local (порты закрыты),
  #   даже если в llm-mode.env осталось LLM_HOST=0.0.0.0.
  #
  #   `nixos-firewall-tool reset` сбрасывает ВСЕ временные правила,
  #   не только LLM-порты. Если начнёшь открывать через него другие
  #   порты — переделай local на точечное удаление.
  #
  # ВАЖНО про Podman:
  #   `-p 5747:5747` без IP публикует порт на 0.0.0.0 — это делает
  #   podman, не мы. Закрытие доступа из LAN обеспечивает фаервол:
  #   пока порт не открыт, входящие из LAN отбрасываются, даже если
  #   podman слушает 0.0.0.0.
  #
  # ВАЖНО про сервисы:
  #   Команда НЕ перезапускает сервисы. Она только пишет файл
  #   и дёргает фаервол. Чтобы изменения подхватились, сервис надо
  #   перезапустить вручную или он сам должен читать EnvironmentFile
  #   при старте:
  #     EnvironmentFile = "-%h/.local/state/llm-mode.env"
  #     ExecStart = "... --host ''${LLM_HOST} ..."
  environment.systemPackages = [
    pkgs.nixos-firewall-tool

    (pkgs.writeShellApplication {
      name = "llm";
      runtimeInputs = [
        pkgs.iproute2
        pkgs.coreutils
        pkgs.iptables
        pkgs.nftables
        pkgs.nixos-firewall-tool
      ];
      text = ''
        set -euo pipefail

        MODE_FILE="$HOME/.local/state/llm-mode.env"
        PORTS="${portsStr}"
        PORTS_RE="${portsRe}"

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

        case "''${1:-}" in
          local)
            set_mode "127.0.0.1"
            echo "Сбрасываю временные правила фаервола..."
            sudo nixos-firewall-tool reset
            echo "Готово. Перезапусти LLM-сервисы вручную, когда удобно."
            ;;
          global)
            set_mode "0.0.0.0"
            echo "Открываю TCP-порты в фаерволе (временно, до reboot'а или llm local):"
            for p in $PORTS; do
              echo "  $p"
              sudo nixos-firewall-tool open tcp "$p"
            done
            echo "Готово. Перезапусти LLM-сервисы вручную, когда удобно."
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
            echo "Слушают порты ($PORTS):"
            ss -tln 2>/dev/null | grep -E ":($PORTS_RE)\b" || echo "  (ничего из ожидаемого)"
            echo
            echo "Фаервол (временные правила):"
            FW_RULES=$(sudo nft list ruleset 2>/dev/null; sudo iptables -S 2>/dev/null || true)
            for p in $PORTS; do
              if echo "$FW_RULES" | grep -qE "dport $p "; then
                echo "  $p — открыт"
              else
                echo "  $p — не найден"
              fi
            done
            ;;
          *)
            echo "Usage: llm {local|global|status}" >&2
            echo "  local  — только 127.0.0.1, сброс временных правил фаервола" >&2
            echo "  global — 0.0.0.0, временное открытие TCP-портов: $PORTS" >&2
            echo "  status — текущий режим, порты и правила фаервола" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];
}
