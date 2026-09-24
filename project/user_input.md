Проект настройки  NIXOS (миграция с fedora silverblue)

0) ТЕКУЩИЙ ФАЙЛ ЯВЛЯЕТСЯ ТЗ И НИКОГДА НЕ ИЗМЕНЯЕТСЯ АГЕНТОМ ИИ САМОСТОЯТЕЛЬНО.

1) устройства

Конфиг будет использоваться на разных устройствах
-Asus z13 AMD halo strix 128gb
-Asus ноутбук на базе процессора Intel
-PC AMD CPU +NVIDIA GPU

Для начала настраиваем nixos на текущем компьютере z13 но закладываем в архитектуру папок и файлов что hardware config будет разный для разных устройств.
при этом например будут скрипты для управления подсветкой клавиатуры для Asus ноутбуков но не для PC

2) GIT
весь конфиг должен храниться в GIT https://github.com/GemmaLover/nix.git

3) Структура хранения конфига

Корневая папка nix

nix/base - папка настройки системы которые будут шариться между устройствами по умолчанию 
nix/base/system - настройки сети, dns, шифрование, насктройки пользователей, клавиатуры, горясие клавиши, wifi и тд
будут храниться файлы вроде notebook_keyboard.nix, wifi.nix, git.nix, luks.nix, network.nix и тд
nix/base/ui  - будут храниться различные конфиги для работы под разными оболочками, вроде kde. по умолчанию настраиваем kde.nix
nix/base/tools - утилиты и программы которые устанавливаются на все устаройства, вроде git, libreoffice, firefox, vlc, docker, podman
nix/base/system/scripts - хранение различных скриптов упрощаюших жизнь, автоматизация, ярлыки и тд


nix/devices - папка для хранения конфигов специфичных для конкретных девайсов, к примеру
nix/devices/z13 - папка с специфичными настройками для z13, например nix/devices/z13/specific/kernel.nix с настройками ядра для устройства
а корне папки хранится файл который собирает как конструктор настройку под конкретное устройство nix/devices/z13/config.nix
и уже внутри  nix/devices/z13/config.nix подключаются файлы
nix/devices/z13/specific/*
nix/base 
и например тут будет 
nix/dev
nix/llm
но не будет
nix/games

в nix/devices/z13/current - текущие настройки, на которых работает z13, с которых начинаем


nix/devices/pc - pc - допустимое todo
nix/devices/asus5304uv - асус ноутубук на intel - допустимое todo


nix/games - хранение настроек программ вроде steam, игр и других вещей связанных с играми. например steam.nix
nix/dev - хранение настроек необходимых для разработки под android, web пример android.nix, waydroid.nix, python.nix и тд
nix/llm - хранение настроек для инференса и работы с llm локально, вроде deepseekharness.nix, unsloth.nix                      

nix/project - рабочая папка где хранится ход работы над проектом
nix/project/log/console24092026.log - сюда записываются все команды введенные в терминал для будущего анализа или выявления проблем. Файлы только дополняются, не затираются. создаются с названием по текущей дате

nix/project/user_input.md -текущий файл с требованием пользователя, не меняется

nix/project/agents.md - сгенерированный, проработанный файл с требованиями к проекту, который может выполняться итерационно в несколько подходов, дополняться по мере проблем и тд
nix/project/problems.md - файл для логирования описания и решением каких-то проблем которые нельзя решить и про которые агенты должны знать чтобы снова на них не попадаться, если вдруг сбросится контекст и тд

nix/project/progress.md - файл с прогрессом по работе над проектом. Никаких todo в генерируемых конфигах. Агент не останавливается пока залача все еще не решена, и только когда она решена - агент переходит к следующей задаче, помечая предыдушую как решенную а текущую как решаемую.

nix/project/projcet.md - список всех требований который будет реализован, генерируется на основе текущего файла.

nix/guide.md - гайд как использовать конфиг из гита при уже установленной системе nixos и при чистой установке nixos на новом устройстве (изза настроект шифрования luks есть вероятность что нельзя будет применить конфиг уже после установки системы)

4) Ожидаемый вид конфига
конфиг должен быть выполнен на devops faang enterprise level 9999
Сам я новчиек nix но планирую разбираться. Конаждая строка конфига nix описана и оснознана, должна быть причина почему она добавлена и эта причина описана перед этой строкой в комментарии

Сейчас я вижу это как то что в системе nixos рядом с файлом configurations я просто добавляю туда папку из гита и потом в configurations пишу что то вроде import nix/devices/z13/config.nix перезагружаюсь и мне применяются все настройки для этого устройства. (как описано выше) - но моего опыта не хватает чтобы понять какое тут best practies решение, предоставь варианты мне на выбор, объясни плюсы и минусы и на основе моего ответа уже запланируй решение



5)
Программы ставить из официальных иточников, не пересборки непойми кем!

Список базовых программ base
какаято база вроде   

shadow  # newuidmap, newgidmap
  coreutils  # grep, cut, tr, mktemp, etc.
  gnutar gzip  # для распаковки образов
  util-linux  # setpriv и другие утилиты
    # --- Системные утилиты ---

    vim
    tree
    file
    which
    
    wget
    curl
    unzip
    git
    htop
    btop
    

apparmor - в режиме обучения

safing.io portmaster - нужны доп настройки systemd для корректной работы

sing-box - настройки сети и прокси

нужно решение для dns doh и dnscrypt, на windows использовал https://github.com/DNSCrypt/SimpleDnsCrypt но нужно и для nix




Список базовых программ base tools


amnezia vpn клиент официальный https://github.com/amnezia-vpn/amnezia-client/releases/tag/5.0.3.0

protonvpn https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://protonvpn.com/%3Fsrsltid%3DAU7gw4WrRIJ60F-fmY9iAY1W0cqh_I_4RVXm5jV9RkCxoMFUcGRZbRgA&ved=2ahUKEwjL1e28-4eXAxVUEhAIHWq8BiIQFnoECA8QAQ&usg=AOvVaw3A33nEd-S8ykwEtNXlDeiq


по возможности используй flatpack версии с минимальными правами для приложений для дополнительной безопасности

остальные программы качаются в папку nix/distrib - папка не под гитов

libre office

vlc

aimp - https://aimp.ru/?do=download&os=linux - версия 6+ linux НЕ НА ОСНОВЕ WINE


firefox



sublime text https://www.sublimetext.com/ 

keepassxc https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://keepassxc.org/&ved=2ahUKEwjq7bKm-YeXAxVjFRAIHQGsGPEQFnoECC0QAQ&usg=AOvVaw0GREmLtjYA-Xb8CLck3BWh 

qbittorrent https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://www.qbittorrent.org/&ved=2ahUKEwjvubTA-YeXAxW1HBAIHUqUIcYQFnoECA8QAQ&usg=AOvVaw05b-bNJuj-xQyxAlteRxfc

obs

kleopatra для pgp ключей

kritia

librewolf
brave
putty
zenmap
parabolic https://github.com/nickvisionapps/parabolic



список программ dev:

android studio устанавливается через flatpack

podman

docker c ui

waydroid сразу с образами

llm раздел:
Ранее стояла fedora silverblue 

Для работы с ллм на полных скоростях нужны доп настройки пользователя:

sudo usermod -aG kvm,libvirt $USER

ls -l /dev/kvm
groups

sudo usermod -aG kvm $USER

llm программы:
программы для работы с llm будут обновляться и самостоятельно по тому кажется лучшим решением поставить их внутрь разных podman образов

- https://unsloth.ai/ в свой unlosth-podman подман с найстройками доступом к локальной сети и рабочей папке с проектами home/projects
нужен ярлык на запуск podman и открытие программы и второй ярлык на закрвтие програамы и остановку этого podman  

- https://github.com/deepseek-ai/deepseek-harness - собирается прямо из гит проекта. гит проект качается в папку home/llm/dsharness оттуда запускается через dsharness podman
нужны яплыки на запуск и открытие веб странички и на закрытие программы и отключение podman



игры:
steam
lutris
heroic games launcher


6)
необходимые настройки системы nixos в целом:
Система должна хоршо работать как на windows-mac системах
- подсветка клавиатуры отключается спустя 15 секунд idle компьютера (пользователь не печатает и не трогает тачпад )
-при печати текста блочится тачпад чтобы не было ложных срабатываний.
-при просмотре фильмов в firefox или vlc экран не гаснет, система не уходит в сон
-Звук на высоком уровне
- переключения языка через CAPSLOCK при этом сам CAPSLOCK не включается, и текст не становится набираться заглавными
-две раскладки English US и RU Russian. При старте системы всегда US. при смене раскладки в системе - язык сохраняется для всех окон


7) настройки для z13 - специфичные для текущего устройства

раньше стояла fedora silverblue и для настройки работы llm требовались доп настройки распределения памяти:

sudo rpm-ostree kargs --append="amdgpu.gttsize=113777 ttm.pages_limit=29126912"


так же необходимо установить утилиты из 
https://github.com/aic0d3r/z13-tablet-kit - режимы планшета, проверить что и как устанавливатся, заолгировать, подготовить деинсталятор

https://github.com/aic0d3r/z13ctl-plus
и
https://github.com/aic0d3r/z13gui-plus

для управления производительностью z13

8) для каждой строки с установленными программами выставляется оценка сколько gb займет диска


сгенерируй план, необходимые данные. начни реализацию. жду в итоге файлы md и nix
тк мы в режиме чата, отдельно шлю содержимое 
nix/devices/z13/current 

configuration.nix

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.initrd.luks.devices."luks-c4892993-c483-4bc4-afeb-0549d71d2959".device = "/dev/disk/by-uuid/c4892993-c483-4bc4-afeb-0549d71d2959";
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Moscow";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    # jack.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."lexi" = {
    isNormalUser = true;
    description = "lexi";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}


hardware-configuration.nix

# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/mapper/luks-758e76c9-2be7-4008-92fa-cd78f7f2ea1c";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-758e76c9-2be7-4008-92fa-cd78f7f2ea1c".device = "/dev/disk/by-uuid/758e76c9-2be7-4008-92fa-cd78f7f2ea1c";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/B652-F5CD";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices =
    [ { device = "/dev/mapper/luks-c4892993-c483-4bc4-afeb-0549d71d2959"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
