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
  # На роутере использовался прозрачный режим (--transparent),
  # здесь — SOCKS5 (без --transparent), потому что sing-box
  # перенаправляет Brave на 127.0.0.1:6430 через socks5.
  #
  # Изменения относительно роутера:
  #  - убран --ip 0.0.0.0 (слушаем только 127.0.0.1)
  #  - убран --transparent (используем SOCKS5)
  #  - порт 1080 → 6430
  #  - путь к hosts: /etc/config/byedpi.hosts → /etc/byedpi/hosts.txt
  #
  # ВАЖНО:
  # - ByeDPI — это SOCKS5, не VLESS. Он не шифрует трафик,
  #   а маскирует его от DPI (TCP-десинхронизация).
  # - sing-box перенаправляет Brave на byedpi-out (127.0.0.1:6430).
  #   Правило process_name = ["ciadpi"] с action = "bypass"
  #   в sing-box предотвращает петлю.
  # =====================================================================
  services.byedpi = {
    enable = true;

    # Порт и hosts + стратегии с роутера.
    extraArgs = [
      # --- Базовые параметры ---
      "-p" "6430"
      "--hosts" "/etc/byedpi/hosts.txt"
      "--debug" "2"

      # --- Стратегии обхода DPI (скопированы с роутера as-is) ---
      # Первая группа: "disorder" + split для разных позиций
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

      # Вторая группа: то же самое ещё раз (в конфиге роутера
      # стратегия продублирована — оставляем как есть, работает)
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
  # Список хостов с роутера (полный).
  #
  # Каждая строка — один домен или CIDR. ByeDPI применит стратегии
  # только к соединениям, чей SNI (HTTPS) или Host (HTTP) совпадает
  # с одним из этих доменов.
  #
  # Источник: /etc/config/byedpi.hosts с рабочего OpenWrt-роутера.
  # =====================================================================
  environment.etc."byedpi/hosts.txt".text = ''
    # === YouTube / Google ===
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

    # === Новости ===
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

    # === Погода ===
    accuweather.com
    meteoblue.com
    open-meteo.com
    openweathermap.org
    weatherstack.com
    worldweatheronline.com
    wunderground.com

    # === Мессенджеры / соцсети ===
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

    # === Торренты / медиа ===
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

    # === Книги ===
    lib.rus.ec
    flibusta.is
    flibs.me
    flisland.net
    flibusta.site

    # === Приватность / VPN ===
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

    # === Проверка утечек ===
    whois.domaintools.com
    dnsleaktest.com
    ipleak.net
    dnscheck.tools
    check.torproject.org

    # === DNS / Cloudflare ===
    cloudflare.com
    cloudflare-dns.com
    1dot1dot1dot1.cloudflare-dns.com
    controld.com
    umbrella.com
    cisco.com
    quad9.net

    # === Разработка / репозитории ===
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

    # === Akamai / CDN ===
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

    # === Прочее ===
    4pda.to
    startpage.com
    yoa3d.com
    rambler.ru
    NS1.google.com
    NS2.google.com
    NS3.google.com
    NS4.google.com

    # === CIDR-диапазоны (IP-подсети) ===
    149.34.0.0/16
    23.192.0.0/11
    23.128.64.0/23
  '';

  # =====================================================================
  # Автозапуск и зависимости сервиса.
  # =====================================================================
  systemd.services.byedpi = {
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      WantedBy = [ "multi-user.target" ];
    };
  };
}
