# Цей скрипт призначений для чистої конфігурації.
# Якщо роутер вже працює — спочатку:
# /system backup save name=before-production
# /export file=before-production
# Потім
# /system reset-configuration no-defaults=yes skip-backup=yes
# Після reboot підключаєшся через WinBox → MAC Address.
# Треба змінити тільки один раз
# На початку скрипта є:
# :local ADMIN_USER "roman"
# :local ADMIN_PASSWORD "CHANGE_ME_STRONG_ADMIN_PASSWORD"
# :local WIFI_PASSWORD "CHANGE_ME_STRONG_WIFI_PASSWORD"
# :local LAPTOP_PUBLIC_KEY "CHANGE_ME_LAPTOP_PUBLIC_KEY"
# :local PHONE_PUBLIC_KEY "CHANGE_ME_PHONE_PUBLIC_KEY"
# :local PC_PUBLIC_KEY "CHANGE_ME_PC_PUBLIC_KEY"
# Змінюєш тільки ці значення.
 
# MikroTik hAP ac - Production Configuration
# RouterOS 7.x
#
# Hardware:
#   MikroTik hAP ac
#
# Network:
#   WAN        = ether1
#   LAN        = bridge-LAN
#   LAN subnet = 192.168.88.0/24
#   Gateway    = 192.168.88.1
#   DHCP       = 192.168.88.5-192.168.88.35
#
# WireGuard:
#   Router     = 10.99.0.1
#   Laptop     = 10.99.0.2
#   Phone      = 10.99.0.3
#   PC         = 10.99.0.4
#   UDP port   = 51820
#
# Management:
#   SSH        = 2241
#   WinBox     = 48291
#
# Comments:
#   Explanatory comments are Ukrainian.
#   RouterOS comment= values are English.
#
# IMPORTANT:
#   Change all CHANGE_ME_* values before deployment.
 
 
# 00. VARIABLES
:local ADMIN_USER "roman"
:local ADMIN_PASSWORD "CHANGE_ME_STRONG_ADMIN_PASSWORD"
:local WIFI_PASSWORD "CHANGE_ME_STRONG_WIFI_PASSWORD"
:local LAPTOP_PUBLIC_KEY "CHANGE_ME_LAPTOP_PUBLIC_KEY"
:local PHONE_PUBLIC_KEY "CHANGE_ME_PHONE_PUBLIC_KEY"
:local PC_PUBLIC_KEY "CHANGE_ME_PC_PUBLIC_KEY"
 
# 01. SYSTEM IDENTITY
/system identity
set name="MikroTik-hAP-ac"
 
# 02. CLOCK / TIMEZONE
/system clock
set time-zone-name=Europe/Kyiv
 
# 03. NTP
/system ntp client
set enabled=yes
 
# 04. INTERFACE LISTS
# Створюємо логічні групи:
# WAN = Internet
# LAN = local network
# VPN = WireGuard
# Firewall буде працювати через ці списки,
# а не через конкретні фізичні інтерфейси.
/interface list
add name=WAN comment="Internet interfaces"
add name=LAN comment="Trusted local interfaces"
add name=VPN comment="WireGuard VPN interfaces"
 
# 05. LAN BRIDGE
/interface bridge
add name=bridge-LAN \
    protocol-mode=rstp \
    comment="Main LAN bridge"
 
# 06. ETHERNET PORTS
# ether1 = WAN
# ether2-ether5 = LAN
/interface bridge port
add bridge=bridge-LAN interface=ether2 comment="LAN port 2"
add bridge=bridge-LAN interface=ether3 comment="LAN port 3"
add bridge=bridge-LAN interface=ether4 comment="LAN port 4"
add bridge=bridge-LAN interface=ether5 comment="LAN port 5"
 
# 07. INTERFACE LIST MEMBERS
/interface list member
add interface=ether1 list=WAN comment="WAN interface"
add interface=bridge-LAN list=LAN comment="Main LAN bridge"
 
# 08. LAN IP
/ip address
add address=192.168.88.1/24 \
    interface=bridge-LAN \
    comment="Main LAN gateway"
 
# 09. WAN DHCP
# Провайдер повинен видавати IP через DHCP.
/ip dhcp-client
add interface=ether1 \
    add-default-route=yes \
    use-peer-dns=no \
    use-peer-ntp=no \
    comment="WAN DHCP client"
 
# 10. DHCP POOL
/ip pool
add name=pool-LAN \
    ranges=192.168.88.5-192.168.88.35 \
    comment="Main LAN DHCP pool"
 
# 11. DHCP SERVER
/ip dhcp-server
add name=dhcp-LAN \
    interface=bridge-LAN \
    address-pool=pool-LAN \
    lease-time=1d \
    authoritative=yes \
    comment="Main LAN DHCP server"
/ip dhcp-server network
add address=192.168.88.0/24 \
    gateway=192.168.88.1 \
    dns-server=192.168.88.1 \
    comment="Main LAN DHCP network"
 
# 12. DNS
# MikroTik працює DNS resolver для LAN та WireGuard.
# Доступ до DNS буде дозволений firewall тільки
# з trusted networks.
/ip dns
set allow-remote-requests=yes \
    servers=1.1.1.1,9.9.9.9 \
    cache-size=4096KiB
 
# 13. IP CLOUD DDNS
# Включаємо MikroTik Cloud DDNS.
# Після отримання WAN IP виконай:
# /ip cloud print
# Там буде:
# dns-name: xxxxxxxxxxxx.sn.mynetname.net
# Саме це ім'я можна використати як Endpoint
# у WireGuard клієнтах.
# MikroTik Cloud перевіряє зміну зовнішньої адреси
# та оновлює DNS record.
/ip cloud
set ddns-enabled=yes \
    update-time=yes
 
# 14. WIREGUARD INTERFACE
# VPN subnet:
# 10.99.0.0/24
#
# MikroTik:
# 10.99.0.1
#
# Clients:
# 10.99.0.2
# 10.99.0.3
# 10.99.0.4
/interface wireguard
add name=wireguard-home \
    listen-port=51820 \
    mtu=1420 \
    comment="Main WireGuard VPN"
 
# 15. WIREGUARD IP
/ip address
add address=10.99.0.1/24 \
    interface=wireguard-home \
    comment="WireGuard gateway"
/interface list member
add interface=wireguard-home \
    list=VPN \
    comment="WireGuard VPN interface"
 
# 16. WIREGUARD PEER - LAPTOP
/interface wireguard peers
add interface=wireguard-home \
    public-key=$LAPTOP_PUBLIC_KEY \
    allowed-address=10.99.0.2/32 \
    comment="WireGuard laptop"
 
# 17. WIREGUARD PEER - PHONE
/interface wireguard peers
add interface=wireguard-home \
    public-key=$PHONE_PUBLIC_KEY \
    allowed-address=10.99.0.3/32 \
    comment="WireGuard phone"
 
# 18. WIREGUARD PEER - PC
/interface wireguard peers
add interface=wireguard-home \
    public-key=$PC_PUBLIC_KEY \
    allowed-address=10.99.0.4/32 \
    comment="WireGuard PC"
 
# 19. TRUSTED NETWORK ADDRESS LIST
/ip firewall address-list
add list=TRUSTED_NETWORKS \
    address=192.168.88.0/24 \
    comment="Trusted LAN network"
add list=TRUSTED_NETWORKS \
    address=10.99.0.0/24 \
    comment="Trusted WireGuard network"
 
# 20. LOCAL NETWORKS
/ip firewall address-list
add list=LOCAL_NETWORKS \
    address=192.168.88.0/24 \
    comment="Main LAN network"
add list=LOCAL_NETWORKS \
    address=10.99.0.0/24 \
    comment="WireGuard network"
 
# 21. BOGON NETWORKS
# RFC1918 та інші спеціальні IPv4 діапазони.
# Вони використовуються для блокування підроблених
# source addresses з WAN.
/ip firewall address-list
add list=BOGONS address=0.0.0.0/8 comment="This network"
add list=BOGONS address=10.0.0.0/8 comment="Private network"
add list=BOGONS address=100.64.0.0/10 comment="Carrier grade NAT"
add list=BOGONS address=127.0.0.0/8 comment="Loopback"
add list=BOGONS address=169.254.0.0/16 comment="Link local"
add list=BOGONS address=172.16.0.0/12 comment="Private network"
add list=BOGONS address=192.0.0.0/24 comment="IETF protocol assignments"
add list=BOGONS address=192.0.2.0/24 comment="Documentation network"
add list=BOGONS address=192.168.0.0/16 comment="Private network"
add list=BOGONS address=198.18.0.0/15 comment="Benchmark network"
add list=BOGONS address=198.51.100.0/24 comment="Documentation network"
add list=BOGONS address=203.0.113.0/24 comment="Documentation network"
add list=BOGONS address=224.0.0.0/4 comment="Multicast"
add list=BOGONS address=240.0.0.0/4 comment="Reserved network"
 
# 22. RAW FIREWALL
# RAW працює до connection tracking.
# Блокуємо явно неправильні джерела з WAN.
# Це зменшує навантаження на connection tracking.
/ip firewall raw
add chain=prerouting \
    action=drop \
    in-interface-list=WAN \
    src-address-list=BOGONS \
    comment="Drop bogon source addresses"
 
# 23. SSH BRUTE FORCE PROTECTION
# Оскільки SSH не доступний з WAN, цей механізм є
# додатковим захистом для LAN/VPN.
# Якщо хтось багато разів помиляється з паролем,
# його адреса потрапляє до blacklist.
/ip firewall filter
add chain=input \
    action=add-src-to-address-list \
    address-list=SSH_BLACKLIST \
    address-list-timeout=1d \
    protocol=tcp \
    dst-port=2241 \
    connection-state=new \
    src-address-list=SSH_STAGE3 \
    comment="Blacklist repeated SSH attacks"
add chain=input \
    action=add-src-to-address-list \
    address-list=SSH_STAGE3 \
    address-list-timeout=1h \
    protocol=tcp \
    dst-port=2241 \
    connection-state=new \
    src-address-list=SSH_STAGE2 \
    comment="Track SSH brute force stage 3"
add chain=input \
    action=add-src-to-address-list \
    address-list=SSH_STAGE2 \
    address-list-timeout=15m \
    protocol=tcp \
    dst-port=2241 \
    connection-state=new \
    src-address-list=SSH_STAGE1 \
    comment="Track SSH brute force stage 2"
add chain=input \
    action=add-src-to-address-list \
    address-list=SSH_STAGE1 \
    address-list-timeout=5m \
    protocol=tcp \
    dst-port=2241 \
    comment="Track SSH brute force stage 1"
add chain=input \
    action=drop \
    src-address-list=SSH_BLACKLIST \
    comment="Drop blacklisted SSH sources"
 
# 24. INPUT FIREWALL
# Захищаємо сам MikroTik.
# Порядок:
# established/related
# invalid
# ICMP
# WireGuard
# DNS
# management
# final drop
add chain=input \
    action=accept \
    connection-state=established,related \
    comment="Allow established and related input"
add chain=input \
    action=drop \
    connection-state=invalid \
    comment="Drop invalid input"
# ICMP потрібен для нормальної діагностики,
# PMTU та роботи мережі.
/ip firewall filter
add chain=input \
    action=accept \
    protocol=icmp \
    comment="Allow ICMP"
 
# 25. WIREGUARD HANDSHAKE
# UDP 51820 з WAN — єдиний новий сервіс,
# який дозволяємо приймати з Internet.
/ip firewall filter
add chain=input \
    action=accept \
    protocol=udp \
    dst-port=51820 \
    in-interface-list=WAN \
    comment="Allow WireGuard from Internet"
 
# 26. DNS FROM TRUSTED NETWORKS
/ip firewall filter
add chain=input \
    action=accept \
    protocol=udp \
    dst-port=53 \
    src-address-list=TRUSTED_NETWORKS \
    comment="Allow DNS UDP from trusted networks"
add chain=input \
    action=accept \
    protocol=tcp \
    dst-port=53 \
    src-address-list=TRUSTED_NETWORKS \
    comment="Allow DNS TCP from trusted networks"
 
# 27. WINBOX
# WinBox НЕ доступний з Internet.
# Доступ:
# LAN + WireGuard
#
# Port:
# 48291
/ip firewall filter
add chain=input \
    action=accept \
    protocol=tcp \
    dst-port=48291 \
    src-address-list=TRUSTED_NETWORKS \
    comment="Allow WinBox from trusted networks"
 
# 28. SSH
# SSH НЕ доступний з Internet.
# Port:
# 2241
/ip firewall filter
add chain=input \
    action=accept \
    protocol=tcp \
    dst-port=2241 \
    src-address-list=TRUSTED_NETWORKS \
    src-address-list=!SSH_BLACKLIST \
    comment="Allow SSH from trusted networks"
 
# 29. VPN TO ROUTER
/ip firewall filter
add chain=input \
    action=accept \
    src-address=10.99.0.0/24 \
    comment="Allow WireGuard clients to router"
 
# 30. FINAL INPUT DROP
# Все інше до самого роутера блокуємо.
/ip firewall filter
add chain=input \
    action=drop \
    comment="Drop all other input"
 
# 31. FORWARD FIREWALL
# Forward = traffic through router.
/ip firewall filter
add chain=forward \
    action=accept \
    connection-state=established,related \
    comment="Allow established and related forwarding"
add chain=forward \
    action=drop \
    connection-state=invalid \
    comment="Drop invalid forwarding"
 
# 32. FASTTRACK
# FastTrack не застосовуємо до VPN.
# Це дозволяє WireGuard traffic проходити звичайним
# firewall path.
# LAN <-> Internet отримує прискорення.
/ip firewall filter
add chain=forward \
    action=fasttrack-connection \
    connection-state=established,related \
    in-interface-list=LAN \
    out-interface-list=WAN \
    comment="FastTrack LAN to Internet"
add chain=forward \
    action=fasttrack-connection \
    connection-state=established,related \
    in-interface-list=WAN \
    out-interface-list=LAN \
    comment="FastTrack Internet to LAN replies"
 
# 33. LAN -> INTERNET
/ip firewall filter
add chain=forward \
    action=accept \
    in-interface-list=LAN \
    out-interface-list=WAN \
    connection-state=new \
    comment="Allow LAN to Internet"
 
# 34. VPN -> INTERNET
/ip firewall filter
add chain=forward \
    action=accept \
    in-interface-list=VPN \
    out-interface-list=WAN \
    connection-state=new \
    comment="Allow VPN to Internet"
 
# 35. VPN -> LAN
/ip firewall filter
add chain=forward \
    action=accept \
    in-interface-list=VPN \
    out-interface-list=LAN \
    comment="Allow VPN to LAN"
 
# 36. LAN -> VPN
/ip firewall filter
add chain=forward \
    action=accept \
    in-interface-list=LAN \
    out-interface-list=VPN \
    comment="Allow LAN to VPN"
 
# 37. BLOCK UNSOLICITED WAN
# WAN не може ініціювати з'єднання до LAN/VPN.
/ip firewall filter
add chain=forward \
    action=drop \
    connection-state=new \
    in-interface-list=WAN \
    connection-nat-state=!dstnat \
    comment="Drop unsolicited WAN forwarding"
 
# 38. FINAL FORWARD DROP
/ip firewall filter
add chain=forward \
    action=drop \
    comment="Drop all other forwarding"
 
# 39. NAT - LAN
/ip firewall nat
add chain=srcnat \
    action=masquerade \
    src-address=192.168.88.0/24 \
    out-interface-list=WAN \
    comment="Masquerade LAN to Internet"
 
# 40. NAT - WIREGUARD
/ip firewall nat
add chain=srcnat \
    action=masquerade \
    src-address=10.99.0.0/24 \
    out-interface-list=WAN \
    comment="Masquerade WireGuard to Internet"
 
# 41. IP SERVICES
# Вимикаємо все непотрібне.
# WinBox:
#   48291
# SSH:
#   2241
/ip service
set [find name=telnet] disabled=yes
set [find name=ftp] disabled=yes
set [find name=www] disabled=yes
set [find name=www-ssl] disabled=yes
set [find name=api] disabled=yes
set [find name=api-ssl] disabled=yes
set [find name=winbox] \
    disabled=no \
    port=48291 \
    address=192.168.88.0/24,10.99.0.0/24
set [find name=ssh] \
    disabled=no \
    port=2241 \
    address=192.168.88.0/24,10.99.0.0/24
 
# 42. SSH HARDENING
/ip ssh
set strong-crypto=yes \
    forwarding-enabled=no \
    always-allow-password-login=yes
 
# 43. DISABLE PROXY
/ip proxy
set enabled=no
 
# 44. DISABLE SOCKS
/ip socks
set enabled=no
 
# 45. DISABLE UPnP
/ip upnp
set enabled=no
 
# 46. DISABLE BANDWIDTH SERVER
/tool bandwidth-server
set enabled=no
 
# 47. MAC SERVER
# MAC access залишаємо тільки LAN.
# Це потрібно для аварійного WinBox MAC access.
# WAN MAC access повністю заборонений.
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/tool mac-server ping
set enabled=no
 
# 48. NEIGHBOR DISCOVERY
# MikroTik discovery тільки LAN.
/ip neighbor discovery-settings
set discover-interface-list=LAN
 
# 49. IPv6
# Якщо провайдер/мережа не використовує IPv6,
# найкраща production-політика — не залишати його
# випадково відкритим.
# IPv6 firewall нижче також створюємо.
# Якщо IPv6 реально потрібен у майбутньому,
# спочатку треба налаштувати IPv6 addressing,
# DHCPv6-PD/RA та IPv6 routing,
# а потім увімкнути IPv6.
/ipv6 settings
set disable-ipv6=yes
 
# 50. IPv6 FIREWALL - DEFENSE IN DEPTH
# Правила залишаємо підготовленими, але IPv6 вимкнений.
# Якщо IPv6 буде увімкнений:
# ці правила потрібно активувати/перевірити
# відповідно до IPv6 topology.
/ipv6 firewall filter
add chain=input \
    action=accept \
    connection-state=established,related \
    comment="Allow established and related IPv6 input"
add chain=input \
    action=drop \
    connection-state=invalid \
    comment="Drop invalid IPv6 input"
add chain=input \
    action=accept \
    protocol=icmpv6 \
    comment="Allow ICMPv6 input"
add chain=input \
    action=drop \
    in-interface-list=WAN \
    comment="Drop unsolicited IPv6 WAN input"
add chain=input \
    action=drop \
    comment="Drop all other IPv6 input"
add chain=forward \
    action=accept \
    connection-state=established,related \
    comment="Allow established and related IPv6 forwarding"
add chain=forward \
    action=drop \
    connection-state=invalid \
    comment="Drop invalid IPv6 forwarding"
add chain=forward \
    action=accept \
    protocol=icmpv6 \
    comment="Allow ICMPv6 forwarding"
add chain=forward \
    action=drop \
    in-interface-list=WAN \
    comment="Drop unsolicited IPv6 WAN forwarding"
add chain=forward \
    action=drop \
    comment="Drop all other IPv6 forwarding"
 
# 51. USER
# Створюємо окремого адміністратора.
# ВАЖЛИВО:
# Пароль задається змінною на початку скрипта.
/user
add name=$ADMIN_USER \
    group=full \
    password=$ADMIN_PASSWORD \
    address=192.168.88.0/24,10.99.0.0/24 \
    comment="Primary network administrator"
 
# 52. DISABLE DEFAULT ADMIN
# Після створення нового користувача вимикаємо
# стандартний admin.
/user
set [find name=admin] disabled=yes
 
# 53. SYSTEM LOGGING
/system logging
add topics=firewall \
    action=memory \
    comment="Firewall logging"
add topics=wireguard \
    action=memory \
    comment="WireGuard logging"
 
# 54. AUTOMATIC CONFIGURATION BACKUP
# Створюємо script, який генерує:
#   .backup
#   .rsc
# Файли залишаються на router storage.
# Backup містить sensitive information,
# тому доступ до нього має бути захищений.
/system script
add name=production-backup \
    policy=ftp,read,write,policy,test,sensitive \
    comment="Create production configuration backup" \
    source={
        :local routerName [/system identity get name];
        :local date [/system clock get date];
        :local time [/system clock get time];
        :local safeDate [:pick $date 0 11];
        :local safeTime [:pick $time 0 8];
        :local prefix ("backup-" . $safeDate . "-" . $safeTime);
        /system backup save name=$prefix;
        /export file=$prefix;
        :log info ("Production backup created: " . $prefix);
    }
 
# 55. DAILY BACKUP SCHEDULER
/system scheduler
add name=production-backup-daily \
    interval=1d \
    start-time=03:30:00 \
    on-event=production-backup \
    policy=ftp,read,write,policy,test,sensitive \
    comment="Daily production backup"
 
# 56. AUTOMATIC OLD BACKUP CLEANUP
# Видаляємо старі backup-файли, щоб storage
# не заповнився.
# Зберігаємо останні файли за часом створення.
# Для production не видаляємо backup автоматично
# безпечним "all files" алгоритмом.
# Замість цього залишаємо cleanup manual,
# щоб випадково не втратити recovery point.
 
# 57. EXPORT CURRENT CONFIGURATION
/export file=production-final
 
# 58. CREATE BINARY BACKUP
/system backup save name=production-final
 
# 59. FINAL STATUS
:put ""
:put "============================================================"
:put " MikroTik hAP ac - Production 2.0"
:put "============================================================"
:put ""
:put "LAN"
:put "  Gateway:        192.168.88.1"
:put "  Network:        192.168.88.0/24"
:put "  DHCP:           192.168.88.5-192.168.88.35"
:put ""
:put "WIREGUARD"
:put "  Gateway:        10.99.0.1"
:put "  Laptop:         10.99.0.2"
:put "  Phone:          10.99.0.3"
:put "  PC:             10.99.0.4"
:put "  UDP port:       51820"
:put ""
:put "MANAGEMENT"
:put "  SSH:            2241"
:put "  WinBox:         48291"
:put ""
:put "SECURITY"
:put "  WAN management: BLOCKED"
:put "  WireGuard:      ENABLED"
:put "  IPv6:           DISABLED"
:put "  UPnP:            DISABLED"
:put "  SOCKS:           DISABLED"
:put "  Proxy:           DISABLED"
:put "  MAC WAN access:  BLOCKED"
:put ""
:put "BACKUP"
:put "  Daily backup:    03:30"
:put ""
:put "IMPORTANT"
:put "  Check /ip cloud print"
:put "  Check WireGuard peers"
:put "  Test LAN before disconnecting"
:put "============================================================"
