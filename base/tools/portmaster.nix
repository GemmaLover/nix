{ config, lib, pkgs, inputs, ... }:

{
  # === Safing Portmaster ===
  # Application firewall + DNS-фильтр с графическим клиентом.
  # Модуль и пакет берутся из nixpkgs-unstable, так как в стабильном
  # 26.05 их пока нет (появятся в 26.11).
  #
  # ВАЖНО: Portmaster поднимает собственный DNS-сервер на порту 53.
  # Если в системе уже есть dnscrypt-proxy или systemd-resolved,
  # они будут конфликтовать за порт. Перед включением нужно
  # убедиться, что оба отключены (см. base/system/dns.nix).

  services.portmaster = {
    enable = true;

    settings = {

     # Указываем Portmaster использовать наш локальный dnscrypt-proxy
      # в качестве вышестоящего DNS-сервера.
      # Синтаксис: dns://IP:порт
      "dns/nameservers" = [
        "dns://127.0.0.1:5353"
      ];

      # Уровень логирования — warning, чтобы не забивать журнал.
      "core/log/level" = "warning";
    };
  };
}
