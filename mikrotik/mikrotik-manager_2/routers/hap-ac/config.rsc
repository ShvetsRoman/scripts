# =============================================================================
# MikroTik hAP AC (RB962UiGS-5HacT2HnT) — домашня конфігурація
# RouterOS 7.20+ | драйвер Wi-Fi вибирається вручну в wifiDriver
# =============================================================================
# Перед застосуванням:
# 1. Замініть усі ЗАМІНІТЬ_* та задайте routerPassword для setup.sh.
# 2. Для WAN-адміністрування задайте wanAdminAddresses і відповідні тумблери.
# 3. WireGuard endpoint налаштовується у клієнтському профілі; цей файл
#    створює серверний інтерфейс та peer.
# 4. Рекомендовано застосовувати на чистій конфігурації через setup.sh --reset.
# =============================================================================

# =============================================================================
# 0. ПАРАМЕТРИ
# =============================================================================

# Підключення setup.sh
:global routerHost "192.168.88.1"
:global routerUser "admin-lb"
:global routerPassword ""
# Порти SSH та Winbox, які слухає роутер; SSH-порт також використовує setup.sh.
# Якщо змінюєте порт — додайте його до bfPorts.
:global routerSshPort 22
:global routerWinboxPort 8291
:global configFile "config.rsc"

# Система та адміністратор
:global routerIdentity "hap-ac-home"
:global TIMEZONE "Europe/Kyiv"
:global ntpServer1 "ua.pool.ntp.org"
:global ntpServer2 "time.cloudflare.com"
:global adminUser "admin-lb"
:global adminPassword "ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА"

# Основні перемикачі
:global enableGuest true
:global enableIot true
:global enableWifi2Ghz true
:global enableWifi5Ghz true
:global enableBruteforce true
# IPv6: вимкнений за замовчуванням (протокол відключається на рівні стеку).
:global enableIPv6 false

# WAN-доступ до адміністрування — вимкнений за замовчуванням.
# wanAdminAddresses — один або кілька довірених IP/CIDR через кому, наприклад "203.0.113.8/32".
:global enableWanSsh false
:global enableWanWinbox false
:global wanAdminAddresses ""

# Мережа та VLAN
:global wanInterface "ether1"
:global bridgeName "br-lan"
:global lanPorts {"ether2";"ether3";"ether4";"ether5"}
:global vlanLan 10
:global vlanGuest 20
:global vlanIot 30
:global vifLan "vlan10-lan"
:global vifGuest "vlan20-guest"
:global vifIot "vlan30-iot"
:global netLan "192.168.10.0/24"
:global netGuest "192.168.20.0/24"
:global netIot "192.168.30.0/24"
:global ipLan "192.168.10.1/24"
:global ipGuest "192.168.20.1/24"
:global ipIot "192.168.30.1/24"
:global gwLan "192.168.10.1"
:global gwGuest "192.168.20.1"
:global gwIot "192.168.30.1"
:global poolLan "192.168.10.100-192.168.10.199"
:global poolGuest "192.168.20.100-192.168.20.199"
:global poolIot "192.168.30.100-192.168.30.199"
:global leaseLan "8h"
:global leaseGuest "2h"
:global leaseIot "8h"
:global dnsUpstream "1.1.1.1,9.9.9.9"

# Wi-Fi
# Допустимі значення: legacy | wifi-qcom-ac | wifi-qcom
# Якщо обидва діапазони вимкнені, цей параметр не використовується.
:global wifiDriver "legacy"
# Для нових драйверів вкажіть default-name фізичних радіо конкретного пристрою.
:global wifi2GhzInterface "wifi2"
:global wifi5GhzInterface "wifi1"
:global wifiSsid "Home-WiFi"
:global wifiPassword "ЗАМІНІТЬ_ПАРОЛЬ_WIFI"
:global guestSsid "Home-Guest"
:global guestPassword "ЗАМІНІТЬ_ПАРОЛЬ_ГОСТЯ"
:global iotSsid "Home-IoT"
:global iotPassword "ЗАМІНІТЬ_ПАРОЛЬ_IOT"

# WireGuard: ip | mikrotik-ddns | disabled
:global wgEndpointMode "mikrotik-ddns"
:global wgEndpointIp ""
:global wgPort 13231
:global wgAddr "10.10.100.1/24"
:global wgNet "10.10.100.0/24"
:global wgPeerAddr "10.10.100.2/32"
:global wgPeerKey "ЗАМІНІТЬ_КЛЮЧ_WG"
# Доступ SSH/Winbox через WireGuard-тунель (джерела з wgNet).
:global enableWgSsh true
:global enableWgWinbox true

# Захист від перебору нових TCP-з'єднань на SSH/Winbox із WAN.
# Містить routerSshPort та routerWinboxPort; при зміні портів оновіть список.
:global bfPorts "22,8291"
:global bfStageTimeout "1m"
:global bfBlacklistTime "10d"

# =============================================================================
# 0а. ПЕРЕВІРКА ПАРАМЕТРІВ
# =============================================================================

:if (($enableGuest != true) and ($enableGuest != false)) do={:error "enableGuest має бути true або false"}
:if (($enableIot != true) and ($enableIot != false)) do={:error "enableIot має бути true або false"}
:if (($enableWifi2Ghz != true) and ($enableWifi2Ghz != false)) do={:error "enableWifi2Ghz має бути true або false"}
:if (($enableWifi5Ghz != true) and ($enableWifi5Ghz != false)) do={:error "enableWifi5Ghz має бути true або false"}
:if (($enableBruteforce != true) and ($enableBruteforce != false)) do={:error "enableBruteforce має бути true або false"}
:if (($enableIPv6 != true) and ($enableIPv6 != false)) do={:error "enableIPv6 має бути true або false"}
:if (($enableWanSsh != true) and ($enableWanSsh != false)) do={:error "enableWanSsh має бути true або false"}
:if (($enableWanWinbox != true) and ($enableWanWinbox != false)) do={:error "enableWanWinbox має бути true або false"}
:if (($enableWifi2Ghz = true) or ($enableWifi5Ghz = true)) do={
    :if (($wifiDriver != "legacy") and ($wifiDriver != "wifi-qcom-ac") and ($wifiDriver != "wifi-qcom")) do={:error "wifiDriver: дозволено legacy, wifi-qcom-ac або wifi-qcom"}
}
:if (($wgEndpointMode != "ip") and ($wgEndpointMode != "mikrotik-ddns") and ($wgEndpointMode != "disabled")) do={:error "wgEndpointMode: дозволено ip, mikrotik-ddns або disabled"}
:if ($adminPassword = "ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА") do={:error "Замініть adminPassword перед імпортом"}
:if ((($enableWifi2Ghz = true) or ($enableWifi5Ghz = true)) and ($wifiPassword = "ЗАМІНІТЬ_ПАРОЛЬ_WIFI")) do={:error "Замініть wifiPassword перед імпортом"}
:if (($enableGuest = true) and ($enableWifi2Ghz = true) and ($guestPassword = "ЗАМІНІТЬ_ПАРОЛЬ_ГОСТЯ")) do={:error "Замініть guestPassword перед імпортом"}
:if (($enableIot = true) and ($enableWifi2Ghz = true) and ($iotPassword = "ЗАМІНІТЬ_ПАРОЛЬ_IOT")) do={:error "Замініть iotPassword перед імпортом"}
:if (($wgEndpointMode != "disabled") and ($wgPeerKey = "ЗАМІНІТЬ_КЛЮЧ_WG")) do={:error "Замініть wgPeerKey перед імпортом"}
:if (($enableWanSsh = true) or ($enableWanWinbox = true)) do={
    :if ([:len $wanAdminAddresses] = 0) do={:error "Для WAN-адміністрування задайте wanAdminAddresses із довіреними IP/CIDR"}
}
:if (($wgEndpointMode = "ip") and ([:len $wgEndpointIp] = 0)) do={:error "Для wgEndpointMode=ip задайте wgEndpointIp"}
:if (([:typeof $wgPort] != "num") or ($wgPort < 1) or ($wgPort > 65535)) do={:error "wgPort має бути числом 1..65535"}
:if (($wgEndpointMode != "disabled") and ([:len $wgPeerKey] = 0)) do={:error "Для WireGuard задайте публічний ключ клієнта wgPeerKey"}
:if (([:typeof $routerWinboxPort] != "num") or ($routerWinboxPort < 1) or ($routerWinboxPort > 65535)) do={:error "routerWinboxPort має бути числом 1..65535"}
:if ($routerWinboxPort = $routerSshPort) do={:error "routerWinboxPort не може збігатися з routerSshPort"}
:if (($enableWgSsh != true) and ($enableWgSsh != false)) do={:error "enableWgSsh має бути true або false"}
:if (($enableWgWinbox != true) and ($enableWgWinbox != false)) do={:error "enableWgWinbox має бути true або false"}

# =============================================================================
# 1. СИСТЕМА, ЧАС, ЖУРНАЛ
# =============================================================================

/system identity set name=$routerIdentity
/system clock set time-zone-name=$TIMEZONE
/system ntp client set enabled=yes
/system ntp client servers remove [find]
/system ntp client servers add address=$ntpServer1 comment="NTP Україна"
/system ntp client servers add address=$ntpServer2 comment="NTP Cloudflare"

/system note set show-at-login=yes note="Authorization required. Unauthorized access is prohibited."

# IPv6: enableIPv6=false вимикає стек протоколу (адреси очищаються; повна
# дія застосовується після перезавантаження). enableIPv6=true лишає стек
# увімкненим — окремий IPv6 firewall цей профіль не налаштовує.
:if ($enableIPv6 = true) do={
    /ipv6 settings set disable-ipv6=no
} else={
    /ipv6 settings set disable-ipv6=yes
}

# =============================================================================
# 2. КОРИСТУВАЧІ
# =============================================================================

:if ([:len [/user find where name=$adminUser]] = 0) do={
    /user add name=$adminUser group=full password=$adminPassword comment="Основний адміністратор"
} else={
    /user set [find where name=$adminUser] group=full password=$adminPassword
}
:if ($adminUser != "admin") do={
    :if ([:len [/user find where name="admin"]] > 0) do={/user disable [find where name="admin"]}
}

# =============================================================================
# 3. BRIDGE, VLAN ТА СПИСКИ ІНТЕРФЕЙСІВ
# =============================================================================

# frame-types задаються на кожному bridge-порті, а не на самому мосту.
/interface bridge add name=$bridgeName protocol-mode=rstp vlan-filtering=no comment="Основний міст LAN"
:foreach p in=$lanPorts do={
    /interface bridge port add bridge=$bridgeName interface=$p pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Дротовий LAN"
}

/interface vlan add name=$vifLan vlan-id=$vlanLan interface=$bridgeName comment="Основна мережа"
:if ($enableGuest = true) do={/interface vlan add name=$vifGuest vlan-id=$vlanGuest interface=$bridgeName comment="Гостьова мережа"}
:if ($enableIot = true) do={/interface vlan add name=$vifIot vlan-id=$vlanIot interface=$bridgeName comment="Мережа IoT"}

/interface list add name=WAN comment="Зовнішній інтерфейс"
/interface list add name=LAN comment="Основна мережа та VPN"
/interface list add name=LAN-L2 comment="Фізичні LAN-порти для MAC Winbox та discovery"
/interface list member add list=WAN interface=$wanInterface
/interface list member add list=LAN interface=$vifLan
:foreach p in=$lanPorts do={/interface list member add list=LAN-L2 interface=$p}
:if ($enableGuest = true) do={
    /interface list add name=GUEST comment="Гостьова мережа"
    /interface list member add list=GUEST interface=$vifGuest
}
:if ($enableIot = true) do={
    /interface list add name=IOT comment="IoT мережа"
    /interface list member add list=IOT interface=$vifIot
}

# =============================================================================
# 4. WI-FI
# =============================================================================
# Коли обидва діапазони вимкнені, не виконуємо жодної команди Wi-Fi.
# Драйвер задається вручну; перевірка сумісності з моделлю не виконується.

:if (($enableWifi2Ghz = true) or ($enableWifi5Ghz = true)) do={
    :if ($wifiDriver = "legacy") do={
        # ------------------------------------------------------------
        # Legacy: /interface wireless
        # ------------------------------------------------------------
        /interface wireless security-profiles add name=sec-home mode=dynamic-keys authentication-types=wpa2-psk group-ciphers=aes-ccm unicast-ciphers=aes-ccm wpa2-pre-shared-key=$wifiPassword disable-pmkid=yes comment="Основний Wi-Fi"

        :if ($enableWifi2Ghz = true) do={
            /interface wireless set wlan1 disabled=no mode=ap-bridge band=2ghz-b/g/n channel-width=20/40mhz-eC country=ukraine ssid=$wifiSsid security-profile=sec-home hide-ssid=no wireless-protocol=802.11 comment="Основний Wi-Fi 2.4 GHz"
            /interface bridge port add bridge=$bridgeName interface=wlan1 pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 2.4 GHz LAN"
            /interface list member add list=LAN-L2 interface=wlan1
        } else={/interface wireless set wlan1 disabled=yes}

        :if ($enableWifi5Ghz = true) do={
            /interface wireless set wlan2 disabled=no mode=ap-bridge band=5ghz-a/n/ac channel-width=20/40/80mhz-eeeC country=ukraine ssid=$wifiSsid security-profile=sec-home hide-ssid=no wireless-protocol=802.11 comment="Основний Wi-Fi 5 GHz"
            /interface bridge port add bridge=$bridgeName interface=wlan2 pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 5 GHz LAN"
            /interface list member add list=LAN-L2 interface=wlan2
        } else={/interface wireless set wlan2 disabled=yes}

        :if (($enableGuest = true) and ($enableWifi2Ghz = true)) do={
            /interface wireless security-profiles add name=sec-guest mode=dynamic-keys authentication-types=wpa2-psk group-ciphers=aes-ccm unicast-ciphers=aes-ccm wpa2-pre-shared-key=$guestPassword disable-pmkid=yes comment="Гостьовий Wi-Fi"
            /interface wireless add name=wlan1-guest master-interface=wlan1 mode=ap-bridge ssid=$guestSsid security-profile=sec-guest vlan-mode=no-tag default-forwarding=no disabled=no comment="Гостьовий Wi-Fi 2.4 GHz"
            /interface bridge port add bridge=$bridgeName interface=wlan1-guest pvid=$vlanGuest ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Guest Wi-Fi"
        }
        :if (($enableIot = true) and ($enableWifi2Ghz = true)) do={
            /interface wireless security-profiles add name=sec-iot mode=dynamic-keys authentication-types=wpa2-psk group-ciphers=aes-ccm unicast-ciphers=aes-ccm wpa2-pre-shared-key=$iotPassword disable-pmkid=yes comment="IoT Wi-Fi"
            /interface wireless add name=wlan1-iot master-interface=wlan1 mode=ap-bridge ssid=$iotSsid security-profile=sec-iot vlan-mode=no-tag default-forwarding=no disabled=no comment="IoT Wi-Fi 2.4 GHz"
            /interface bridge port add bridge=$bridgeName interface=wlan1-iot pvid=$vlanIot ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="IoT Wi-Fi"
        }
    } else={
        # ------------------------------------------------------------
        # Нові драйвери: /interface wifi
        # Для wifi-qcom-ac застосовуються 802.11n/ac; для wifi-qcom — ax.
        # Гостьові та IoT інтерфейси отримують VLAN через bridge PVID.
        # ------------------------------------------------------------
        :if ($wifiDriver = "wifi-qcom-ac") do={
            :if ($enableWifi2Ghz = true) do={
                /interface wifi set [find where default-name=$wifi2GhzInterface] disabled=no configuration.mode=ap configuration.country=Ukraine configuration.ssid=$wifiSsid channel.band=2ghz-n channel.width=20/40mhz security.authentication-types=wpa2-psk security.passphrase=$wifiPassword security.wps=disable
                /interface bridge port add bridge=$bridgeName interface=$wifi2GhzInterface pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 2.4 GHz LAN"
                /interface list member add list=LAN-L2 interface=$wifi2GhzInterface
            } else={/interface wifi set [find where default-name=$wifi2GhzInterface] disabled=yes}
            :if ($enableWifi5Ghz = true) do={
                /interface wifi set [find where default-name=$wifi5GhzInterface] disabled=no configuration.mode=ap configuration.country=Ukraine configuration.ssid=$wifiSsid channel.band=5ghz-ac channel.width=20/40/80mhz security.authentication-types=wpa2-psk security.passphrase=$wifiPassword security.wps=disable
                /interface bridge port add bridge=$bridgeName interface=$wifi5GhzInterface pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 5 GHz LAN"
                /interface list member add list=LAN-L2 interface=$wifi5GhzInterface
            } else={/interface wifi set [find where default-name=$wifi5GhzInterface] disabled=yes}
        } else={
            # wifi-qcom: Wi-Fi 6 / 802.11ax
            :if ($enableWifi2Ghz = true) do={
                /interface wifi set [find where default-name=$wifi2GhzInterface] disabled=no configuration.mode=ap configuration.country=Ukraine configuration.ssid=$wifiSsid channel.band=2ghz-ax channel.width=20/40mhz security.authentication-types=wpa2-psk security.passphrase=$wifiPassword security.wps=disable
                /interface bridge port add bridge=$bridgeName interface=$wifi2GhzInterface pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 2.4 GHz LAN"
                /interface list member add list=LAN-L2 interface=$wifi2GhzInterface
            } else={/interface wifi set [find where default-name=$wifi2GhzInterface] disabled=yes}
            :if ($enableWifi5Ghz = true) do={
                /interface wifi set [find where default-name=$wifi5GhzInterface] disabled=no configuration.mode=ap configuration.country=Ukraine configuration.ssid=$wifiSsid channel.band=5ghz-ax channel.width=20/40/80mhz security.authentication-types=wpa2-psk security.passphrase=$wifiPassword security.wps=disable
                /interface bridge port add bridge=$bridgeName interface=$wifi5GhzInterface pvid=$vlanLan ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Wi-Fi 5 GHz LAN"
                /interface list member add list=LAN-L2 interface=$wifi5GhzInterface
            } else={/interface wifi set [find where default-name=$wifi5GhzInterface] disabled=yes}
        }

        # Guest та IoT створюються лише на радіо 2.4 GHz.
        :if (($enableGuest = true) and ($enableWifi2Ghz = true)) do={
            /interface wifi add name=wifi-guest master-interface=$wifi2GhzInterface configuration.mode=ap configuration.ssid=$guestSsid security.authentication-types=wpa2-psk security.passphrase=$guestPassword datapath.client-isolation=yes disabled=no comment="Гостьовий Wi-Fi"
            /interface bridge port add bridge=$bridgeName interface=wifi-guest pvid=$vlanGuest ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="Guest Wi-Fi"
        }
        :if (($enableIot = true) and ($enableWifi2Ghz = true)) do={
            /interface wifi add name=wifi-iot master-interface=$wifi2GhzInterface configuration.mode=ap configuration.ssid=$iotSsid security.authentication-types=wpa2-psk security.passphrase=$iotPassword datapath.client-isolation=yes disabled=no comment="IoT Wi-Fi"
            /interface bridge port add bridge=$bridgeName interface=wifi-iot pvid=$vlanIot ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged comment="IoT Wi-Fi"
        }
    }
}

# VLAN membership: окремий запис на кожний VLAN. Порти доступу з PVID
# автоматично відображаються як untagged; тут явно задаємо CPU tagged.
/interface bridge vlan add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanLan
:if ($enableGuest = true) do={/interface bridge vlan add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanGuest}
:if ($enableIot = true) do={/interface bridge vlan add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanIot}
/interface bridge set [find where name=$bridgeName] vlan-filtering=yes

# =============================================================================
# 5. WAN DHCP
# =============================================================================

/ip dhcp-client remove [find where interface=$wanInterface]
/ip dhcp-client add interface=$wanInterface add-default-route=yes use-peer-dns=no use-peer-ntp=no disabled=no comment="WAN DHCP від провайдера"

# =============================================================================
# 6. IP-АДРЕСИ ТА DHCP
# =============================================================================

/ip address add address=$ipLan interface=$vifLan comment="Шлюз LAN"
/ip pool add name=pool-lan ranges=$poolLan
/ip dhcp-server add name=dhcp-lan interface=$vifLan address-pool=pool-lan lease-time=$leaseLan disabled=no
/ip dhcp-server network add address=$netLan gateway=$gwLan dns-server=$gwLan

:if ($enableGuest = true) do={
    /ip address add address=$ipGuest interface=$vifGuest comment="Шлюз GUEST"
    /ip pool add name=pool-guest ranges=$poolGuest
    /ip dhcp-server add name=dhcp-guest interface=$vifGuest address-pool=pool-guest lease-time=$leaseGuest disabled=no
    /ip dhcp-server network add address=$netGuest gateway=$gwGuest dns-server=$gwGuest
}
:if ($enableIot = true) do={
    /ip address add address=$ipIot interface=$vifIot comment="Шлюз IOT"
    /ip pool add name=pool-iot ranges=$poolIot
    /ip dhcp-server add name=dhcp-iot interface=$vifIot address-pool=pool-iot lease-time=$leaseIot disabled=no
    /ip dhcp-server network add address=$netIot gateway=$gwIot dns-server=$gwIot
}

# =============================================================================
# 7. DNS
# =============================================================================

/ip dns set servers=$dnsUpstream allow-remote-requests=yes max-udp-packet-size=1232 cache-size=2048KiB

# =============================================================================
# 8. WIREGUARD — endpoint mode визначає адресу для клієнтського профілю
# =============================================================================

:if ($wgEndpointMode != "disabled") do={
    /interface wireguard add name=wg-vpn listen-port=$wgPort mtu=1420 comment="WireGuard для віддаленого доступу"
    /ip address add address=$wgAddr interface=wg-vpn comment="Шлюз WireGuard"
    /interface wireguard peers add interface=wg-vpn public-key=$wgPeerKey allowed-address=$wgPeerAddr comment="Клієнт WireGuard №1"
    /interface list member add list=LAN interface=wg-vpn
    :if ($wgEndpointMode = "mikrotik-ddns") do={/ip cloud set ddns-enabled=yes}
    :if ($wgEndpointMode = "ip") do={/ip cloud set ddns-enabled=no}
}

# Endpoint для клієнтського WireGuard-профілю:
# - ip: <wgEndpointIp>:$wgPort (потрібна доступна з Інтернету IP-адреса);
# - mikrotik-ddns: домен з /ip cloud print + порт $wgPort;
# - disabled: VPN не створюється. DDNS не обходить CGNAT.
# На клієнті AllowedIPs визначайте за потрібним режимом маршрутизації.

# =============================================================================
# 9. FIREWALL, BRUTEFORCE ТА NAT
# =============================================================================

# Довірені WAN-адреси для адміністрування пропускаються ДО bruteforce,
# щоб власні IP не потрапляли до динамічного blacklist.
# src-address у firewall приймає лише одне значення — список довірених
# адрес розгортається в окреме правило на кожен IP/CIDR.
:local wanAdminAddr ""
:if ($enableWanSsh = true) do={
    :foreach wanAdminAddr in=[:toarray $wanAdminAddresses] do={
        /ip firewall filter add chain=input action=accept in-interface-list=WAN src-address=$wanAdminAddr protocol=tcp dst-port=$routerSshPort connection-state=new comment="INPUT: SSH з довірених WAN IP"
    }
}
:if ($enableWanWinbox = true) do={
    :foreach wanAdminAddr in=[:toarray $wanAdminAddresses] do={
        /ip firewall filter add chain=input action=accept in-interface-list=WAN src-address=$wanAdminAddr protocol=tcp dst-port=$routerWinboxPort connection-state=new comment="INPUT: Winbox з довірених WAN IP"
    }
}

# Bruteforce: лише нові TCP-з'єднання з WAN на адміністративні порти.
# Правила розміщені у порядку stage3 -> blacklist, stage2 -> stage3,
# stage1 -> stage2, нове джерело -> stage1. add-src-to-address-list є
# passthrough, але попередні стадії вже пройдені поточним пакетом.
:if ($enableBruteforce = true) do={
    /ip firewall filter add chain=input action=drop in-interface-list=WAN protocol=tcp dst-port=$bfPorts src-address-list=bf_blacklist comment="BF: заблоковані джерела на адмін-портах"
    /ip firewall filter add chain=input action=add-src-to-address-list in-interface-list=WAN connection-state=new protocol=tcp tcp-flags=syn,!ack dst-port=$bfPorts src-address-list=bf_stage2 address-list=bf_blacklist address-list-timeout=$bfBlacklistTime comment="BF: stage 2 до blacklist"
    /ip firewall filter add chain=input action=add-src-to-address-list in-interface-list=WAN connection-state=new protocol=tcp tcp-flags=syn,!ack dst-port=$bfPorts src-address-list=bf_stage1 address-list=bf_stage2 address-list-timeout=$bfStageTimeout comment="BF: stage 1 до stage 2"
    /ip firewall filter add chain=input action=add-src-to-address-list in-interface-list=WAN connection-state=new protocol=tcp tcp-flags=syn,!ack dst-port=$bfPorts src-address-list=!bf_stage1 address-list=bf_stage1 address-list-timeout=$bfStageTimeout comment="BF: перша спроба"
}

/ip firewall filter add chain=input action=accept connection-state=established,related comment="INPUT: established/related"
/ip firewall filter add chain=input action=drop connection-state=invalid comment="INPUT: invalid"
/ip firewall filter add chain=input action=accept protocol=icmp comment="INPUT: ICMP для діагностики та PMTU"
/ip firewall filter add chain=input action=accept in-interface-list=LAN comment="INPUT: керування з LAN та WireGuard"

:if ($enableGuest = true) do={
    /ip firewall filter add chain=input action=accept in-interface-list=GUEST protocol=udp dst-port=53 comment="INPUT: DNS UDP Guest"
    /ip firewall filter add chain=input action=accept in-interface-list=GUEST protocol=tcp dst-port=53 comment="INPUT: DNS TCP Guest"
    /ip firewall filter add chain=input action=accept in-interface-list=GUEST protocol=udp dst-port=67 comment="INPUT: DHCP Guest"
    /ip firewall filter add chain=input action=drop in-interface-list=GUEST comment="INPUT: решта Guest до роутера заборонена"
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=input action=accept in-interface-list=IOT protocol=udp dst-port=53 comment="INPUT: DNS UDP IoT"
    /ip firewall filter add chain=input action=accept in-interface-list=IOT protocol=tcp dst-port=53 comment="INPUT: DNS TCP IoT"
    /ip firewall filter add chain=input action=accept in-interface-list=IOT protocol=udp dst-port=67 comment="INPUT: DHCP IoT"
    /ip firewall filter add chain=input action=drop in-interface-list=IOT comment="INPUT: решта IoT до роутера заборонена"
}

:if ($wgEndpointMode != "disabled") do={
    /ip firewall filter add chain=input action=accept in-interface-list=WAN protocol=udp dst-port=$wgPort comment="INPUT: WireGuard з WAN"
}
/ip firewall filter add chain=input action=drop in-interface-list=WAN comment="INPUT: решта WAN заборонена"
/ip firewall filter add chain=input action=drop comment="INPUT: типове блокування"

# FORWARD: заборона між локальними сегментами до загальних дозволів.
/ip firewall filter add chain=forward action=accept connection-state=established,related comment="FORWARD: established/related"
/ip firewall filter add chain=forward action=drop connection-state=invalid comment="FORWARD: invalid"
:if ($enableGuest = true) do={
    /ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$netLan comment="FORWARD: Guest не має доступу до LAN"
    :if ($enableIot = true) do={/ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$netIot comment="FORWARD: Guest не має доступу до IoT"}
    :if ($wgEndpointMode != "disabled") do={/ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$wgNet comment="FORWARD: Guest не має доступу до VPN"}
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$netLan comment="FORWARD: IoT не має доступу до LAN"
    :if ($enableGuest = true) do={/ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$netGuest comment="FORWARD: IoT не має доступу до Guest"}
    :if ($wgEndpointMode != "disabled") do={/ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$wgNet comment="FORWARD: IoT не має доступу до VPN"}
    /ip firewall filter add chain=forward action=accept src-address=$netLan dst-address=$netIot comment="FORWARD: LAN може керувати IoT"
}
/ip firewall filter add chain=forward action=accept in-interface-list=LAN out-interface-list=WAN comment="FORWARD: LAN/VPN до Internet"
:if ($enableGuest = true) do={/ip firewall filter add chain=forward action=accept in-interface-list=GUEST out-interface-list=WAN comment="FORWARD: Guest лише до Internet"}
:if ($enableIot = true) do={/ip firewall filter add chain=forward action=accept in-interface-list=IOT out-interface-list=WAN comment="FORWARD: IoT лише до Internet"}
/ip firewall filter add chain=forward action=drop comment="FORWARD: решта трафіку заборонена"

# NAT лише для мереж, яким дозволений вихід в Інтернет.
/ip firewall address-list
add list=NAT_ALLOWED address=$netLan comment="LAN"
:if ($enableGuest = true) do={add list=NAT_ALLOWED address=$netGuest comment="Guest"}
:if ($enableIot = true) do={add list=NAT_ALLOWED address=$netIot comment="IoT"}
:if ($wgEndpointMode != "disabled") do={add list=NAT_ALLOWED address=$wgNet comment="WireGuard clients"}
/ip firewall nat add chain=srcnat action=masquerade src-address-list=NAT_ALLOWED out-interface-list=WAN comment="NAT: дозволені домашні мережі"

# SYN cookies — правильний шлях RouterOS /ip settings.
/ip settings set tcp-syncookies=yes

# =============================================================================
# 10. СЛУЖБИ ТА ДОСТУП
# =============================================================================

/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api-ssl disabled=yes
# Цільова версія RouterOS >= 7.20, тому available-from застосовується напряму.
# Списки джерел: LAN завжди; wgNet — лише коли WireGuard створюється та
# відповідний тумблер дозволяє доступ через тунель.
:local sshNets $netLan
:local winboxNets $netLan
:if ($wgEndpointMode != "disabled") do={
    :if ($enableWgSsh = true) do={:set sshNets ($sshNets . "," . $wgNet)}
    :if ($enableWgWinbox = true) do={:set winboxNets ($winboxNets . "," . $wgNet)}
}
/ip service set ssh port=$routerSshPort available-from=$sshNets
/ip service set winbox port=$routerWinboxPort available-from=$winboxNets
:if ($enableWanSsh = true) do={/ip service set ssh available-from=$sshNets,$wanAdminAddresses}
:if ($enableWanWinbox = true) do={/ip service set winbox available-from=$winboxNets,$wanAdminAddresses}
/ip ssh set strong-crypto=yes
/tool bandwidth-server set enabled=no
# З RouterOS 7.13 SNMP перенесено з /ip snmp на верхній рівень /snmp.
/snmp set enabled=no
/ip proxy set enabled=no
/ip socks set enabled=no
/ip upnp set enabled=no
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=LAN-L2
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN-L2

# =============================================================================
# 11. ФІНАЛЬНИЙ МАРКЕР
# =============================================================================

/system note set show-at-login=yes note="CONFIG OK — import finished. Authorization required. Unauthorized access is prohibited."

# =============================================================================
# ПІСЛЯ ЗАСТОСУВАННЯ ПЕРЕВІРИТИ:
# /ip dhcp-client print detail
# /interface bridge vlan print
# /ip firewall filter print stats
# /ip dhcp-server lease print
# /interface wireguard print detail
# /ip cloud print (для режиму mikrotik-ddns)
# /ping 1.1.1.1
# =============================================================================
