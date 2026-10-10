# MikroTik hAP ac RB962UiGS-5HacT2HnT / RouterOS 7 / legacy wireless
# Fresh configuration only (no-defaults=yes). Import via local cable / Safe Mode.
# EDIT BEFORE IMPORT: ADMIN_PASSWORD, WIFI_PASSWORD (do not leave placeholders).
# Keep current admin until new login tested. No reset/automatic OS updates here.
:local adminPass "CHANGE_ME_ADMIN_STRONG_PASSWORD"
:local wifiPass "CHANGE_ME_WIFI_STRONG_PASSWORD"
:if (($adminPass = "CHANGE_ME_ADMIN_STRONG_PASSWORD") or ($wifiPass = "CHANGE_ME_WIFI_STRONG_PASSWORD")) do={ :error "Edit ADMIN_PASSWORD and WIFI_PASSWORD before import" }
:if ([:len [/interface wireless find where default-name="wlan1"]] = 0) do={ :error "Legacy wireless wlan1 missing: check wireless package" }
:if ([:len [/interface wireless find where default-name="wlan2"]] = 0) do={ :error "Legacy wireless wlan2 missing: check wireless package" }

/system identity set name="hap-ac-home"
/system clock set time-zone-autodetect=no time-zone-name=Europe/Kyiv
/system ntp client set enabled=yes
/system ntp client servers add address=0.ua.pool.ntp.org
/system ntp client servers add address=1.ua.pool.ntp.org
/system package update set channel=stable
# Updates are manual to avoid unexpected downtime.

# Keep one active administrator; disable old 'admin' only after testing new login.
/user add name=roman group=full password=$adminPass

/interface ethernet
set [find default-name=ether1] name=00_WAN comment="WAN"
set [find default-name=ether2] name=LAN-1-Ethernet
set [find default-name=ether3] name=LAN-2-Ethernet
set [find default-name=ether4] name=LAN-3-Ethernet
set [find default-name=ether5] name=LAN-4-Ethernet
:if ([:len [/interface ethernet find where default-name="sfp1"]] > 0) do={ /interface ethernet set [find default-name="sfp1"] disabled=yes }

/interface wireless
set [find default-name=wlan1] name=LAN-5-wifi_2.4GHz
set [find default-name=wlan2] name=LAN-6-wifi_5GHz
/interface wireless security-profiles
add name=WiFi-security mode=dynamic-keys authentication-types=wpa2-psk \
    unicast-ciphers=aes-ccm group-ciphers=aes-ccm wpa2-pre-shared-key=$wifiPass
/interface wireless
set [find name="LAN-5-wifi_2.4GHz"] mode=ap-bridge band=2ghz-b/g/n \
    channel-width=20mhz frequency=auto country=ukraine frequency-mode=regulatory-domain \
    security-profile=WiFi-security ssid="HOME_test" disabled=no
set [find name="LAN-6-wifi_5GHz"] mode=ap-bridge band=5ghz-a/n/ac \
    channel-width=20/40/80mhz-Ceee frequency=auto country=ukraine frequency-mode=regulatory-domain \
    security-profile=WiFi-security ssid="HOME_test" disabled=no

/interface bridge add name=00_LAN-Bridge protocol-mode=rstp comment="LAN bridge"
/interface bridge port
add bridge=00_LAN-Bridge interface=LAN-1-Ethernet
add bridge=00_LAN-Bridge interface=LAN-2-Ethernet
add bridge=00_LAN-Bridge interface=LAN-3-Ethernet
add bridge=00_LAN-Bridge interface=LAN-4-Ethernet
add bridge=00_LAN-Bridge interface=LAN-5-wifi_2.4GHz
add bridge=00_LAN-Bridge interface=LAN-6-wifi_5GHz

/interface list
add name=WAN comment="Uplink"
add name=LAN comment="Local network"
/interface list member
add list=WAN interface=00_WAN
add list=LAN interface=00_LAN-Bridge

/ip address add address=192.168.88.1/24 interface=00_LAN-Bridge comment="LAN gateway"
/ip pool add name=LAN-Pool ranges=192.168.88.100-192.168.88.200
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1
/ip dhcp-server add name=DHCP-Server interface=00_LAN-Bridge address-pool=LAN-Pool lease-time=12h disabled=no
/ip dhcp-client add interface=00_WAN add-default-route=yes default-route-distance=1 \
    use-peer-dns=no use-peer-ntp=no disabled=no comment="WAN DHCP"
/ip dns set allow-remote-requests=yes servers=1.1.1.3,1.0.0.3

/ip dhcp-server lease
add server=DHCP-Server address=192.168.88.5 mac-address=44:DF:65:6C:14:07 comment="mi_repiter"
add server=DHCP-Server address=192.168.88.6 mac-address=20:10:7A:95:7D:48 comment="printer"
add server=DHCP-Server address=192.168.88.7 mac-address=14:DD:A9:12:69:0C comment="server-pc"
add server=DHCP-Server address=192.168.88.8 mac-address=5C:CF:7F:B8:C5:C2 comment="Signal"
add server=DHCP-Server address=192.168.88.9 mac-address=4C:3B:DF:49:2C:FD comment="X-Box"
add server=DHCP-Server address=192.168.88.10 mac-address=00:25:22:EA:7C:FA comment="Vadim-pc"
add server=DHCP-Server address=192.168.88.11 mac-address=70:77:81:79:F7:37 comment="roman-pc"
add server=DHCP-Server address=192.168.88.12 mac-address=88:46:04:6B:91:02 comment="tel_roman"
add server=DHCP-Server address=192.168.88.13 mac-address=4C:63:71:1C:B8:BC comment="tel_oksana"
add server=DHCP-Server address=192.168.88.14 mac-address=AA:97:75:5F:DD:47 comment="tel_vadim"
add server=DHCP-Server address=192.168.88.15 mac-address=32:30:42:8B:32:66 comment="tel_sasha"
add server=DHCP-Server address=192.168.88.16 mac-address=76:E2:52:AD:FA:F3 comment="planshet_sasha-1"
add server=DHCP-Server address=192.168.88.17 mac-address=FE:40:7E:77:A9:41 comment="planshet_sasha-2"
add server=DHCP-Server address=192.168.88.18 mac-address=74:4C:A1:55:85:0B comment="notebook_sasha"
add server=DHCP-Server address=192.168.88.19 mac-address=D0:78:01:06:66:3B comment="tv_km3-spalnay"
add server=DHCP-Server address=192.168.88.20 mac-address=A0:6F:AA:5E:47:DC comment="tv_lg-32"

/ip firewall address-list add list=trusted_admins address=192.168.88.11 comment="Admin PC"

# NAT: no port forwards enabled by default. Add destination NAT separately.
/ip firewall nat
add chain=srcnat action=masquerade out-interface-list=WAN ipsec-policy=out,none comment="NAT: WAN masquerade"
# Optional forcing LAN DNS to router; uncomment if desired:
# add chain=dstnat action=redirect in-interface-list=LAN protocol=udp dst-port=53 comment="DNS redirect UDP"
# add chain=dstnat action=redirect in-interface-list=LAN protocol=tcp dst-port=53 comment="DNS redirect TCP"

# INPUT: Firewall protects router itself.
/ip firewall filter
add chain=input action=drop connection-state=invalid comment="INPUT: Drop invalid"
add chain=input action=accept connection-state=established,related,untracked comment="INPUT: Established"
add chain=input action=accept protocol=icmp comment="INPUT: ICMP"
add chain=input action=accept in-interface-list=LAN protocol=udp dst-port=67 comment="INPUT: LAN DHCP"
add chain=input action=accept in-interface-list=LAN protocol=udp dst-port=53 comment="INPUT: LAN DNS UDP"
add chain=input action=accept in-interface-list=LAN protocol=tcp dst-port=53 comment="INPUT: LAN DNS TCP"
add chain=input action=accept in-interface-list=LAN src-address-list=trusted_admins protocol=tcp dst-port=2240,48291 comment="INPUT: Trusted admin"
add chain=input action=drop comment="INPUT: Drop other"

# FORWARD: allow new WAN connections only if destination NAT was matched.
/ip firewall filter
add chain=forward action=drop connection-state=invalid comment="FORWARD: Drop invalid"
add chain=forward action=fasttrack-connection connection-state=established,related comment="FORWARD: FastTrack"
add chain=forward action=accept connection-state=established,related,untracked comment="FORWARD: Established"
add chain=forward action=accept connection-state=new in-interface-list=LAN out-interface-list=WAN comment="FORWARD: LAN to WAN"
add chain=forward action=accept connection-state=new connection-nat-state=dstnat in-interface-list=WAN comment="FORWARD: Allow WAN dstnat"
add chain=forward action=drop comment="FORWARD: Drop other"

/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set www-ssl disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set ssh disabled=no port=2240 address=192.168.88.11/32
set winbox disabled=no port=48291 address=192.168.88.11/32
/ip ssh set strong-crypto=yes
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN
/ip upnp set enabled=no
/ip proxy set enabled=no
/ip socks set enabled=no

# Disable unused IPv6 stack if no IPv6 deployment is planned.
# For production IPv6, configure an independent IPv6 firewall first.
/ipv6 settings set disable-ipv6=yes

:put "BASE CONFIG COMPLETE: verify DHCP, Wi-Fi, WAN route and management."
:put "After login as roman succeeds: /user disable [find where name=admin]"
