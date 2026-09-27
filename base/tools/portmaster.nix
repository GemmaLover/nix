{ config, lib, pkgs, ... }:

{
  services.portmaster = {
    enable = true;

    # Глобальные настройки Portmaster.
    settings = {
      "core/log/level" = "warning";
      "dns/nameservers" = [ "dns://127.0.0.1:5353" ];
      "dns/bootstrap-servers" = [ "dns://9.9.9.9" "dns://1.1.1.1" ];
    };

    # Префикс для профилей, чтобы их было легко найти в UI Portmaster.
    profilePrefix = "[NixOS] ";

    # =====================================================================
    # Профили приложений.
    #
    # Portmaster по умолчанию блокирует входящие соединения
    # ("Force Block Incoming Connections"). Для sing-box с TUN это
    # критично: пакеты из singtun0 приходят как входящие и сбрасываются.
    #
    # Создаём профиль для sing-box, в котором filter/blockInbound = false.
    # Portmaster автоматически создаст fingerprint для процесса sing-box
    # (по пути к бинарнику в /nix/store, без хэша), и применит профиль.
    # =====================================================================
    profiles = {
      # Имя профиля (произвольное, будет отображаться в UI).
      SingBox = {
        # Пакет sing-box, из которого Portmaster возьмёт fingerprint.
        # Модуль сам сгенерирует регулярное выражение, игнорирующее
        # хэш и версию в пути /nix/store.
        packages = [ pkgs.sing-box ];

        # Настройки профиля.
        settings = {
          filter = {
            # Разрешить входящие соединения — иначе TUN не работает.
            # Это именно та настройка, которую вы меняли вручную.
            blockInbound = false;
          };
        };
      };
    };
  };

  # =====================================================================
  # Права на config.json выставляем отдельным oneshot-сервисом,
  # который запускается ПОСЛЕ того, как Portmaster создаст файл.
  # Важно: shell — это bash (в coreutils нет /bin/sh),
  # а chmod вызывается явно через coreutils.
  # =====================================================================
  systemd.services.portmaster-config-fix = {
    description = "Make Portmaster config.json readable for GUI";
    after = [ "portmaster.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -f /var/lib/portmaster/config.json ] && break; sleep 1; done; ${pkgs.coreutils}/bin/chmod 644 /var/lib/portmaster/config.json 2>/dev/null || true'";
      RemainAfterExit = true;
    };
  };
}
