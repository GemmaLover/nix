{
  config,
  lib,
  pkgs,
  ...
}: {
  # =====================================================================
  # ByeDPI — локальный SOCKS5-прокси для обхода DPI.
  #
  # Стратегии и список хостов перенесены с рабочего роутера OpenWrt.
  # Отличия от роутера:
  #   - убран --ip 0.0.0.0 (слушаем только 127.0.0.1)
  #   - убран --transparent (используем SOCKS5)
  #   - порт 1080 → 6430
  #   - hosts: /etc/config/byedpi.hosts → /etc/byedpi/hosts.txt
  #
  # Firefox ходит через него (byedpi-out в signbox.nix).
  # ByeDPI сам фильтрует: какие домены обходить, какие форвардить.
  # =====================================================================
  services.byedpi = {
    enable = true;

    extraArgs = [
      # --- Базовые параметры ---
      "-p" "6430"
      "--hosts" "/etc/byedpi/hosts.txt"
      "--debug" "2"

      # --- Стратегии обхода DPI (скопированы с роутера as-is) ---
      "-d1"
      "-d3+s"
      "-s6+s"
      "-d9+s"
      "-s12+s"
      "-d15+s"
      "-s20+s"
      "-d25+s"
      "-s30+s"
      "-d35+s"
      "-r1+s"
      "-S"
      "-a1"
      "-As"

      # Вторая группа (в конфиге роутера стратегия продублирована)
      "-d1"
      "-d3+s"
      "-s6+s"
      "-d9+s"
      "-s12+s"
      "-d15+s"
      "-s20+s"
      "-d25+s"
      "-s30+s"
      "-d35+s"
      "-S"
      "-a1"
    ];
  };

  # =====================================================================
  # Список хостов (полный с роутера).
  #
  # ByeDPI применит стратегии только к соединениям, чей SNI/Host
  # совпадает с одним из доменов. Остальные форвардятся как есть.
  #
  # ВАЖНО: ByeDPI НЕ понимает комментарии в этом файле.
  # Не добавляйте # и текст после доменов — получите
  # "invalid host: num: N" в логах.
  # =====================================================================
  environment.etc."byedpi/hosts.txt".text = ''
    youtube.com
    youtu.be
    ytimg.com
    i.ytimg.com
    i9.ytimg.com
    yt3.ggpht.com
    ggpht.com
    googlevideo.com
    manifests.googlevideo.com
    googleapis.com
    youtube.googleapis.com
    youtubei.googleapis.com
    l.google.com
    wide-youtube.l.google.com
    play.google.com
    googleusercontent.com
    yt3.googleusercontent.com
    gstatic.com
    gmailpostmastertools.googleapis.com
    mtalk.google.com
    1e100.net
    nhacmp3youtube.com
    googleads.g.doubleclick.net

    msnbc.com
    foxnews.com
    cnn.com
    dw.com
    bbc.com
    bbc.co.uk
    static.files.bbci.co.uk
    mybbc-analytics.files.bbci.co.uk
    weather.files.bbci.co.uk
    nav.files.bbci.co.uk
    m.files.bbci.co.uk
    inforesist.org
    france24.com
    currenttime.tv

    accuweather.com
    meteoblue.com
    open-meteo.com
    openweathermap.org
    weatherstack.com
    worldweatheronline.com
    wunderground.com

    whatsapp.com
    whatsapp.net
    static.whatsapp.net
    g.whatsapp.net
    web.whatsapp.com
    time.android.com
    signal.org
    getsession.org
    facebook.com
    x.com
    twitter.com
    instagram.com

    rutracker.org
    rutor.info
    rutor.is
    mega-tor.org
    kinozal.tv
    tapochek.net
    rustorka.com
    fast-torrent.ru
    rezka.ag
    hdrezka.ag
    hdrezka.me
    filmix.co
    filmix.cc
    seasonvar.ru
    edem.tv
    msfree.su

    lib.rus.ec
    flibusta.is
    flibs.me
    flisland.net
    flibusta.site

    safing.io
    wiki.safing.io
    updates.safing.io
    protonvpn.com
    proton.me
    drive.proton.me
    tuta.com
    lastpass.com
    delinea.com
    openvpn.net
    community.openvpn.net

    whois.domaintools.com
    dnsleaktest.com
    ipleak.net
    dnscheck.tools
    check.torproject.org

    cloudflare.com
    cloudflare-dns.com
    1dot1dot1dot1.cloudflare-dns.com
    controld.com
    umbrella.com
    cisco.com
    quad9.net

    github.com
    objects.githubusercontent.com
    openwrt.org
    7-zip.org
    archive.ubuntu.com
    linuxmint.com
    packages.linuxmint.com
    tuxedocomputers.com
    os.tuxedocomputers.com
    mirror.init7.net
    kde.org
    ubuntucinnamon.org
    deb.oxen.io
    ntc.party

    akamaitechnologies.com
    deploy.static.akamaitechnologies.com
    akamaistream.net
    AX0.AKAMAISTREAM.NET
    AX1.AKAMAISTREAM.NET
    AX2.AKAMAISTREAM.NET
    AX3.AKAMAISTREAM.NET
    NS2-32.AKAMAISTREAM.NET
    NS3-32.AKAMAISTREAM.NET
    NS6-32.AKAMAISTREAM.NET
    P5.AKAMAISTREAM.NET
    P6.AKAMAISTREAM.NET
    P7.AKAMAISTREAM.NET
    P8.AKAMAISTREAM.NET
    cloudfront.net
    datapacket.com
    wholesale.adamo.es

    4pda.to
    startpage.com
    yoa3d.com
    rambler.ru
    NS1.google.com
    NS2.google.com
    NS3.google.com
    NS4.google.com

    149.34.0.0/16
    23.192.0.0/11
    23.128.64.0/23
  '';

  # =====================================================================
  # Автозапуск: стартует после network-online.target.
  # =====================================================================
  systemd.services.byedpi = {
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      WantedBy = [ "multi-user.target" ];
    };
  };
}
