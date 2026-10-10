# сброс к заводским настройкам
# /system reset-configuration no-defaults=yes skip-backup=yes

# добавление нового пользователя с полными правами
# /user add name="roman" password="*******" group=full

# деактивация старого пользователя:
# /user set [find name="admin"] disable="yes"

# ## Oбновления ##
# # Выбор канала обновления
# system package update set channel=stable
#
# # Проверка наличия прошивки
# system package update check-for-updates
#
# # Установка прошивки
# system package update download
# system reboot

# Scripts Auto-Update
/system scheduler; :local time "04:00:00"; :do {:set time [get [find name=Update] start-time]} on-error={}; :do {remove Update} on-error={}; add interval=1d name=Update on-event="/system package update; set channel=stable; check-for-updates once; :delay 5; :if ([get installed-version] != [get latest-version]) do={/system scheduler add name=Firmware on-event=\"/system scheduler remove Firmware; /system routerboard; :if ([get current-firmware] != [get upgrade-firmware]) do={upgrade; :delay 1; /system reboot}\" start-time=startup; /system package update install}" start-time=$time

# Устоновка временной зон + SNTP client синхронизация времени
/system clock set time-zone-autodetect=yes time-zone-name=Europe/Kyiv
/system ntp client set enabled=yes mode=unicast servers=0.ua.pool.ntp.org,1.ua.pool.ntp.org,2.ua.pool.ntp.org,3.ua.pool.ntp.org

# Переименование портов
/interface ethernet set [find default-name=ether1] name=00_WAN comment="wan_ethernet"
/interface ethernet set [find default-name=ether2] name=LAN-1-Ethernet comment="lan_1"
/interface ethernet set [find default-name=ether3] name=LAN-2-Ethernet comment="lan_2"
/interface ethernet set [find default-name=ether4] name=LAN-3-Ethernet comment="lan_3"
/interface ethernet set [find default-name=ether5] name=LAN-4-Ethernet comment="lan_4"
/interface ethernet set [find default-name=wlan1] name=LAN-5-wifi_2.4GHz comment="lan_5"
/interface ethernet set [find default-name=wlan2] name=LAN-6-wifi_5GHz comment="lan_6"
# Отключение портов
/interface ethernet set [find name=sfp1] disabled=yes
# /interface wireless set [find name=LAN-6-wifi_5GHz] disabled=yes

# Настройка MikroTik Bridge
/interface bridge add name=00_LAN-Bridge comment="lan_bridge"

# Добавление портов MikroTik в Bridge (LAN, WLAN и тд)
/interface bridge port add bridge=00_LAN-Bridge hw=yes interface=LAN-1-Ethernet
/interface bridge port add bridge=00_LAN-Bridge hw=yes interface=LAN-2-Ethernet
/interface bridge port add bridge=00_LAN-Bridge hw=yes interface=LAN-3-Ethernet
/interface bridge port add bridge=00_LAN-Bridge hw=yes interface=LAN-4-Ethernet
/interface bridge port add bridge=00_LAN-Bridge interface=LAN-5-wifi_2.4GHz
/interface bridge port add bridge=00_LAN-Bridge interface=LAN-6-wifi_5GHz

# Інтерфейс лист
/interface list add name="WAN" comment="wan_interface_list"
/interface list add name="LAN" comment="lan_interface_list"
/interface list member set [find interface=00_WAN] list=WAN
/interface list member set [find interface=00_LAN-Bridge] list=LAN

## Назначение локального IP адреса
# установка ip адреса на выбранный интерфейс
/ip address add address=192.168.88.1/24 interface=00_LAN-Bridge network=192.168.88.0 comment="lan_ip"

## Настройка DCHP сервера в MikroTik
# Определение диапазона назначаемых IP адресов
/ip pool add name=LAN-Pool ranges=192.168.88.5-192.168.88.35 comment="lan_pool"

# Задание сетевых настроек для клиента
/ip dhcp-server network add address=192.168.88.0/24 dns-server=192.168.88.1 gateway=192.168.88.1 netmask=24 comment="dhcp_network"

# Общие настройки MikroTik DCHP сервера
/ip dhcp-server add address-pool=LAN-Pool disabled=no interface=00_LAN-Bridge lease-time=12h name=DHCP-Server comment="dhcp_server"

# Настройка DHCP client в MikroTik
/ip dhcp-client add add-default-route=no dhcp-options=hostname,clientid disabled=no interface=00_WAN comment="dhcp_client"

## Настройка MikroTik DNS
# DNS сервера Cloudflare
/ip dns set allow-remote-requests=yes servers=1.1.1.3,1.0.0.3

## Настройка пароля для WiFi в MikroTik
/interface wireless security-profiles add name=HOME-security authentication-types=wpa2-psk eap-methods="" group-key-update=1h mode=dynamic-keys supplicant-identity=MikroTik wpa2-pre-shared-key=28052013Sasha

# Настройка WiFi на частоте 2,4ГГц
/interface wireless set [ find name=LAN-wifi_2.4GHz ] antenna-gain=0 band=2ghz-b/g/n channel-width=20/40mhz-Ce country=no_country_set disabled=no frequency=auto frequency-mode=manual-txpower mode=ap-bridge security-profile=HOME-security ssid=HOME_test station-roaming=enabled wireless-protocol=802.11

# Настройка WiFi на частоте 5ГГц
/interface wireless set [ find name=LAN-wifi_5GHz ] antenna-gain=0 band=5ghz-a/n/ac channel-width=20/40/80mhz-Ceee country=no_country_set disabled=no frequency=auto frequency-mode=manual-txpower mode=ap-bridge security-profile=HOME_test ssid=HOME_test station-roaming=enabled wireless-protocol=802.11

# Привязка клиентов по MAC адресу
/ip dhcp-server lease add address=192.168.88.5 mac-address=44:DF:65:6C:14:07 server=DHCP-Server comment="mi_repiter"
/ip dhcp-server lease add address=192.168.88.6 mac-address=20:10:7A:95:7D:48 server=DHCP-Server comment="printer"
/ip dhcp-server lease add address=192.168.88.7 mac-address=14:DD:A9:12:69:0C server=DHCP-Server comment="server-pc"
/ip dhcp-server lease add address=192.168.88.8 mac-address=5C:CF:7F:B8:C5:C2 server=DHCP-Server comment="Signal"
/ip dhcp-server lease add address=192.168.88.9 mac-address=4C:3B:DF:49:2C:FD server=DHCP-Server comment="X-Box"
/ip dhcp-server lease add address=192.168.88.10 mac-address=00:25:22:EA:7C:FA server=DHCP-Server comment="Vadim-pc"
/ip dhcp-server lease add address=192.168.88.11 mac-address=70:77:81:79:F7:37 server=DHCP-Server comment="roman-pc"
/ip dhcp-server lease add address=192.168.88.12 mac-address=88:46:04:6B:91:02 server=DHCP-Server comment="tel_roman"
/ip dhcp-server lease add address=192.168.88.13 mac-address=4C:63:71:1C:B8:BC server=DHCP-Server comment="tel_oksana"
/ip dhcp-server lease add address=192.168.88.14 mac-address=AA:97:75:5F:DD:47 server=DHCP-Server comment="tel_vadim"
/ip dhcp-server lease add address=192.168.88.15 mac-address=32:30:42:8B:32:66 server=DHCP-Server comment="tel_sasha"
/ip dhcp-server lease add address=192.168.88.16 mac-address=76:E2:52:AD:FA:F3 server=DHCP-Server comment="planshet_sasha"
/ip dhcp-server lease add address=192.168.88.17 mac-address=FE:40:7E:77:A9:41 server=DHCP-Server comment="planshet_sasha"
/ip dhcp-server lease add address=192.168.88.18 mac-address=74:4C:A1:55:85:0B server=DHCP-Server comment="notebook_sasha"
/ip dhcp-server lease add address=192.168.88.19 mac-address=D0:78:01:06:66:3B server=DHCP-Server comment="tv_km3-spalnay"
/ip dhcp-server lease add address=192.168.88.20 mac-address=A0:6F:AA:5E:47:DC server=DHCP-Server comment="tv_lg-32"


# Проброс портов !!!
/ip firewall nat
# Пользователи локальной сети получают доступ в интернет
add action=masquerade chain=srcnat ipsec-policy=out,none out-interface-list=WAN comment="Local network users gain access to the Internet"
# Если у интернет соединения выделенный IP адрес, то рекомендуется установить:
#Action = src-nat;
#To Addresses = Внешний_IP_Адрес.
