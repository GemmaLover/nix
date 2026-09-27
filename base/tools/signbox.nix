{ config, lib, pkgs, ... }:

{
  # =====================================================================
  # sing-box — маршрутизация TCP-трафика по процессам.
  #
  # Модель трафика (кто чем занимается):
  #   ┌─────────────────────────────────────────────────────────────┐
  #   │ Portmaster (127.0.0.17:53)                                  │
  #   │   - перехватывает DNS через nfqueue                         │
  #   │   - фильтрует и форвардит на dnscrypt-proxy                 │
  #   ├─────────────────────────────────────────────────────────────┤
  #   │ dnscrypt-proxy (127.0.0.1:53 и :5353)                       │
  #   │   - шифрует DNS (DoH/DNSCrypt) → Cloudflare/Quad9/Scaleway  │
  #   │   - пакеты уже зашифрованы                                  │
  #   ├─────────────────────────────────────────────────────────────┤
  #   │ sing-box (TUN singtun0)                                     │
  #   │   - DNS НЕ трогает (это работа Portmaster)                  │
  #   │   - dnscrypt-proxy → direct (пакеты уже зашифрованы)        │
  #   │   - portmaster-core → direct (он сам управляет nfqueue)     │
  #   │   - Brave  → SOCKS5                                         │
  #   │   - Chromium → VLESS                                        │
  #   │   - Firefox, nix, всё остальное → direct                    │
  #   └─────────────────────────────────────────────────────────────┘
  #
  # ВАЖНО:
  #   - DNS-секции нет. sing-box не резолвит имена.
  #   - Правила hijack-dns нет. DNS-фильтрацию делает Portmaster.
  #   - MTU = 1400: предотвращает дропы больших пакетов при выходе
  #     через wlp (MTU 1500). Без этого TLS-хендшейк зависает.
  #   - strict_route = false: strict_route ломает rp_filter при
  #     прямых исходящих через физический интерфейс.
  #   - auto_route требует nftables. Без nft sing-box не может
  #     маркировать пакеты fwmark и его прямые исходящие
  #     зацикливаются через TUN. Поэтому:
  #       а) networking.nftables.enable = true — в base/system/network.nix;
  #       б) nft и iptables добавлены в path сервиса ниже.
  # =====================================================================

  services.sing-box = {
    enable = true;

    settings = {
      log = { level = "info"; };

      # --- Входящий интерфейс: TUN ---
      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          address = [ "172.19.0.1/30" ];
          # auto_route — sing-box сам добавляет маршруты и ip rule
          # через nftables-маркировку (fwmark).
          auto_route = true;
          # strict_route = false — иначе ломается прямой трафик
          # к dnscrypt и portmaster.
          strict_route = false;
          # MTU 1400: безопасно ниже 1500, чтобы пакеты не дропались
          # при выходе через физический интерфейс.
          mtu = 1400;
        }
      ];

      # --- Исходящие подключения ---
      outbounds = [
        # 1. SOCKS5 — для Brave.
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";      # <-- ЗАМЕНИТЕ на адрес SOCKS5-сервера
          server_port = 1080;        # <-- ЗАМЕНИТЕ на порт
          version = "5";
          username = "chelik";
          password = "pass11";
        }

        # 2. VLESS — для Chromium.
        {
          type = "vless";
          tag = "vless-out";
          server = "ВАШ_СЕРВЕР";     # <-- ЗАМЕНИТЕ
          server_port = 443;         # <-- ЗАМЕНИТЕ
          uuid = "ВАШ_UUID";         # <-- ЗАМЕНИТЕ
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = "ВАШ_ДОМЕН";  # <-- ЗАМЕНИТЕ
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
          };
        }

        # 3. Direct — по умолчанию.
        { type = "direct"; tag = "direct-out"; }
      ];

      # --- Маршрутизация ---
      route = {
        # Обязательно для правил process_name / process_path_regex.
        find_process = true;

        # Автоматически определять интерфейс для direct-out.
        auto_detect_interface = true;

        rules = [
          # 1. Loopback — direct.
          # Покрывает обращения к dnscrypt-proxy (127.0.0.1:53 и :5353)
          # и Portmaster (127.0.0.17:53).
          {
            ip_cidr = [ "127.0.0.0/8" "::1/128" ];
            outbound = "direct-out";
          }

          # 2. dnscrypt-proxy → direct.
          # Его пакеты — DoH/DNSCrypt, уже зашифрованы.
          # sing-box не должен их трогать.
          {
            process_name = [ "dnscrypt-proxy" ];
            outbound = "direct-out";
          }

          # 3. Portmaster → direct.
          # Он сам перехватывает DNS через nfqueue и фильтрует.
          # Вмешательство sing-box сломает фильтрацию.
          {
            process_name = [ "portmaster-core" ];
            outbound = "direct-out";
          }

          # 4. Сниффинг доменов — для маршрутизации по домену
          # (например, чтобы *.youtube.com шёл через VLESS).
          # Сейчас используется только для информации в логах.
          { action = "sniff"; }

          # 5. Brave (Flatpak) → SOCKS5.
          {
            process_name = [ "brave" ];
            outbound = "socks-out";
          }
          {
            process_path_regex = [ ".*/brave/brave.*" ];
            outbound = "socks-out";
          }

          # 6. Chromium (Flatpak) → VLESS.
          {
            process_name = [ "chromium" ];
            outbound = "vless-out";
          }
          {
            process_path_regex = [ ".*/chromium/chromium.*" ];
            outbound = "vless-out";
          }

          # 7. Всё остальное → direct.
          # Включает Firefox, nix, прочие браузеры, консольные утилиты.
          { outbound = "direct-out"; }
        ];
      };
    };
  };

  # =====================================================================
  # Настройка systemd-сервиса sing-box.
  #
  # Capabilities:
  #   CAP_NET_ADMIN       — создание TUN, управление маршрутами,
  #                          nftables-правила для auto_route.
  #   CAP_NET_RAW         — сырые сокеты.
  #   CAP_SYS_PTRACE      — чтение /proc/<pid>/exe для process_path_regex.
  #   CAP_NET_BIND_SERVICE — bind к портам <1024 (не критично).
  #
  # PATH:
  #   NixOS-модуль services.sing-box не пробрасывает системный PATH
  #   в сервис — только то, что указано явно. Без nft в PATH
  #   sing-box не может вызывать его для auto_route, и прямые
  #   исходящие зацикливаются через TUN (curl висит, Firefox
  #   не открывает сайты).
  # =====================================================================
  systemd.services.sing-box.serviceConfig = {
    AmbientCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
      "CAP_SYS_PTRACE"
    ];
    CapabilityBoundingSet = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
      "CAP_SYS_PTRACE"
    ];
    # nft — для auto_route и маркировки fwmark.
    # iptables — для совместимости (некоторые версии sing-box
    #            всё ещё вызывают iptables для nft-таблиц).
    # iproute2 — для работы с ip rule и ip route.
    path = [ pkgs.nftables pkgs.iptables pkgs.iproute2 ];
  };
}
