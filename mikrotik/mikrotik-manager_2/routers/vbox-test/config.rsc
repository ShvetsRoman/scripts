# =============================================================================
# ТЕСТОВИЙ ПРОФІЛЬ: MikroTik CHR у VirtualBox (на базі hAP ac²)
# RouterOS: 7.20+ | Файл читається setup.sh
#
# НОВА СХЕМА:
# - WiFi вимкнений: CHR не має радіомодулів; WiFi-команди відсутні повністю.
# - WireGuard керується wgEndpointMode: ip | mikrotik-ddns | disabled.
# - WAN SSH/Winbox керуються enableWanSsh / enableWanWinbox.
# - Доступ через тунель — enableWgSsh / enableWgWinbox; порти служб —
#   routerSshPort та routerWinboxPort.
# - wanAdminAddresses — список довірених зовнішніх IP у форматі
#   "198.51.100.10/32,203.0.113.20/32". Використовуйте власні реальні адреси.
# - Автоматичні бекапи та нічний LED у цьому профілі відсутні.
#
# ПЕРШЕ ПІДКЛЮЧЕННЯ:
# Якщо CHR ще має заводську адресу, тимчасово встановіть routerHost=192.168.88.1.
# Після застосування конфігурації адреса керування стане 192.168.10.1;
# тоді змініть routerHost на 192.168.10.1 для наступних запусків setup.sh.
# На хості для першого підключення: ip addr add 192.168.88.2/24 dev vboxnet0
# Після переходу на нову адресу: ip addr replace 192.168.10.2/24 dev vboxnet0
#
# ЗАСТОСУВАННЯ:
# ./setup.sh --name vbox-test
# ./setup.sh --name vbox-test --reset
# ВРУЧНУ: /import file-name=config.rsc
#
# ВАЖЛИВО: setup.sh читає початкові :global. Не додавайте коментарі в кінець
# рядків :global, які він має розібрати.
# =============================================================================

# =============================================================================
# 0. ЗМІННІ — НАЛАШТУВАННЯ В ОДНОМУ МІСЦІ
# =============================================================================

# --- Підключення setup.sh ---
:global routerHost "192.168.88.1"
:global routerUser "admin"
:global routerPassword "11111111"
# Порти SSH та Winbox, які слухає роутер; SSH-порт також використовує setup.sh.
# Якщо змінюєте порт — додайте його до bfPorts.
:global routerSshPort 22
:global routerWinboxPort 8291
:global configFile "config.rsc"

# --- Система ---
:global routerIdentity "vbox-test1"
:global TIMEZONE "Europe/Kyiv"
:global ntpServer1 "ua.pool.ntp.org"
:global ntpServer2 "time.cloudflare.com"
:global adminUser "roman"
:global adminPassword "11111111"

# --- Мережеві перемикачі ---
:global enableGuest false
:global enableIot false 
# IPv6: вимкнений за замовчуванням (протокол відключається на рівні стеку).
:global enableIPv6 false

# --- WiFi: вимкнений для CHR ---
:global enableWifi2Ghz false
:global enableWifi5Ghz false

# --- WireGuard --- Допустимі значення: ip | mikrotik-ddns | disabled.
:global wgEndpointMode "disabled"
:global wgEndpointIp ""
:global wgPort 13231
:global wgAddr "10.10.100.1/24"
:global wgNet "10.10.100.0/24"
:global wgPeerAddr "10.10.100.2/32"
:global wgPeerKey "ЗАМІНІТЬ_КЛЮЧ_WG"
# Доступ SSH/Winbox через WireGuard-тунель (джерела з wgNet).
:global enableWgSsh true
:global enableWgWinbox true

# --- WAN-адміністрування ---
:global enableWanSsh false
:global enableWanWinbox false
:global wanAdminAddresses ""

# --- Захист від брутфорсу ---
:global enableBruteforce true
:global bfPorts "22,8291"
:global bfStageTimeout "1m"
:global bfBlacklistTime "10d"

# --- Мережа ---
:global wanInterface "ether1"
:global bridgeName "bridge-lan"
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

# =============================================================================
# 0а. ПЕРЕВІРКА ПАРАМЕТРІВ
# =============================================================================

:if (($enableGuest != true) and ($enableGuest != false)) do={:error "enableGuest має бути true або false"}
:if (($enableIot != true) and ($enableIot != false)) do={:error "enableIot має бути true або false"}
:if (($enableIPv6 != true) and ($enableIPv6 != false)) do={:error "enableIPv6 має бути true або false"}
:if (($enableWifi2Ghz != true) and ($enableWifi2Ghz != false)) do={:error "enableWifi2Ghz має бути true або false"}
:if (($enableWifi5Ghz != true) and ($enableWifi5Ghz != false)) do={:error "enableWifi5Ghz має бути true або false"}
:if (($enableBruteforce != true) and ($enableBruteforce != false)) do={:error "enableBruteforce має бути true або false"}
:if (($enableWanSsh != true) and ($enableWanSsh != false)) do={:error "enableWanSsh має бути true або false"}
:if (($enableWanWinbox != true) and ($enableWanWinbox != false)) do={:error "enableWanWinbox має бути true або false"}
:if ($adminPassword = "ЗАМІНІТЬ_НА_ПАРОЛЬ_ADMIN") do={:error "Замініть adminPassword перед імпортом"}
:if (([:typeof $wgPort] != "num") or ($wgPort < 1) or ($wgPort > 65535)) do={:error "wgPort має бути числом 1..65535"}
:if (([:typeof $routerWinboxPort] != "num") or ($routerWinboxPort < 1) or ($routerWinboxPort > 65535)) do={:error "routerWinboxPort має бути числом 1..65535"}
:if ($routerWinboxPort = $routerSshPort) do={:error "routerWinboxPort не може збігатися з routerSshPort"}
:if (($enableWgSsh != true) and ($enableWgSsh != false)) do={:error "enableWgSsh має бути true або false"}
:if (($enableWgWinbox != true) and ($enableWgWinbox != false)) do={:error "enableWgWinbox має бути true або false"}
:if (($enableWanSsh = true) or ($enableWanWinbox = true)) do={
    :if ([:len $wanAdminAddresses] = 0) do={:error "Для WAN-адміністрування задайте wanAdminAddresses із довіреними IP/CIDR"}
}

# =============================================================================
# 1. БАЗОВІ СИСТЕМНІ НАЛАШТУВАННЯ
# =============================================================================

/system identity set name=$routerIdentity
/system clock set time-zone-name=$TIMEZONE

/system ntp client set enabled=yes
/system ntp client servers remove [find]
/system ntp client servers add address=$ntpServer1
/system ntp client servers add address=$ntpServer2

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
# 2. КОРИСТУВАЧІ ТА БЕЗПЕКА АДМІНІСТРУВАННЯ
# =============================================================================

# routerUser (SSH-доступ setup.sh) і adminUser (створюється конфігурацією)
# можуть відрізнятися. Повторний імпорт не повинен створювати дубль користувача.
:if ([:len [/user find where name=$adminUser]] = 0) do={
    /user add name=$adminUser group=full password=$adminPassword comment="Основний адміністратор"
} else={
    /user set [find where name=$adminUser] group=full password=$adminPassword comment="Основний адміністратор"
}

:if ($adminUser != "admin") do={
    :if ([:len [/user find where name="admin"]] > 0) do={ /user disable [find where name="admin"] }
}

# =============================================================================
# 3. ІНТЕРФЕЙСИ, BRIDGE ТА VLAN
# =============================================================================

/interface bridge
:if ([:len [find where name=$bridgeName]] = 0) do={
    add name=$bridgeName vlan-filtering=no protocol-mode=rstp comment="Основний міст LAN"
} else={
    set [find where name=$bridgeName] protocol-mode=rstp
}

/interface bridge port
:foreach p in=$lanPorts do={
    :if ([:len [find where interface=$p]] = 0) do={
        add bridge=$bridgeName interface=$p pvid=$vlanLan comment="LAN-порт"
    } else={
        set [find where interface=$p] bridge=$bridgeName pvid=$vlanLan
    }
}

/interface vlan
:if ([:len [find where name=$vifLan]] = 0) do={
    add name=$vifLan vlan-id=$vlanLan interface=$bridgeName comment="Основна мережа"
}
:if ($enableGuest = true) do={
    :if ([:len [find where name=$vifGuest]] = 0) do={
        add name=$vifGuest vlan-id=$vlanGuest interface=$bridgeName comment="Гостьова мережа"
    }
}
:if ($enableIot = true) do={
    :if ([:len [find where name=$vifIot]] = 0) do={
        add name=$vifIot vlan-id=$vlanIot interface=$bridgeName comment="Мережа IoT"
    }
}

/interface bridge vlan
:if ([:len [find where bridge=$bridgeName and vlan-ids=$vlanLan]] = 0) do={
    add bridge=$bridgeName tagged=$bridgeName untagged=$lanPorts vlan-ids=$vlanLan
}
:if ($enableGuest = true) do={
    :if ([:len [find where bridge=$bridgeName and vlan-ids=$vlanGuest]] = 0) do={
        add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanGuest
    }
}
:if ($enableIot = true) do={
    :if ([:len [find where bridge=$bridgeName and vlan-ids=$vlanIot]] = 0) do={
        add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanIot
    }
}

# Увімкнути VLAN filtering після налаштування bridge VLAN table.
/interface bridge set [find where name=$bridgeName] vlan-filtering=yes

# =============================================================================
# 3а. СПИСКИ ІНТЕРФЕЙСІВ
# =============================================================================

/interface list
:if ([:len [find where name="WAN"]] = 0) do={ add name=WAN }
:if ([:len [find where name="LAN"]] = 0) do={ add name=LAN }

/interface list member
:if ([:len [find where list="WAN" and interface=$wanInterface]] = 0) do={ add interface=$wanInterface list=WAN }
:if ([:len [find where list="LAN" and interface=$vifLan]] = 0) do={ add interface=$vifLan list=LAN }

:if ($enableGuest = true) do={
    /interface list
    :if ([:len [find where name="GUEST"]] = 0) do={ add name=GUEST }
    /interface list member
    :if ([:len [find where list="GUEST" and interface=$vifGuest]] = 0) do={ add interface=$vifGuest list=GUEST }
}
:if ($enableIot = true) do={
    /interface list
    :if ([:len [find where name="IOT"]] = 0) do={ add name=IOT }
    /interface list member
    :if ([:len [find where list="IOT" and interface=$vifIot]] = 0) do={ add interface=$vifIot list=IOT }
}

# =============================================================================
# 4. WiFi — ПОВНІСТЮ ВІДСУТНІЙ У ПРОФІЛІ CHR
# =============================================================================

# =============================================================================
# 5. WAN — DHCP ВІД ВІРТУАЛЬНОГО NAT
# =============================================================================

/ip dhcp-client
remove [find where interface=$wanInterface]
add interface=$wanInterface add-default-route=yes use-peer-dns=no \
    dhcp-options=hostname,clientid disabled=no comment="DHCP-клієнт від провайдера"

# =============================================================================
# 6. IP-АДРЕСИ ТА DHCP-СЕРВЕРИ
# =============================================================================

/ip address
:if ([:len [find where interface=$vifLan and address=$ipLan]] = 0) do={
    add address=$ipLan interface=$vifLan comment="Шлюз LAN"
}

/ip pool
:if ([:len [find where name="pool-lan"]] = 0) do={ add name=pool-lan ranges=$poolLan comment="Пул LAN" } else={ set [find where name="pool-lan"] ranges=$poolLan }

/ip dhcp-server
:if ([:len [find where name="dhcp-lan"]] = 0) do={
    add name=dhcp-lan interface=$vifLan address-pool=pool-lan lease-time=$leaseLan disabled=no comment="DHCP LAN"
} else={
    set [find where name="dhcp-lan"] interface=$vifLan address-pool=pool-lan lease-time=$leaseLan disabled=no
}

/ip dhcp-server network
:if ([:len [find where address=$netLan]] = 0) do={
    add address=$netLan gateway=$gwLan dns-server=$gwLan comment="Мережа LAN"
} else={
    set [find where address=$netLan] gateway=$gwLan dns-server=$gwLan
}

:if ($enableGuest = true) do={
    /ip address
    :if ([:len [find where interface=$vifGuest and address=$ipGuest]] = 0) do={ add address=$ipGuest interface=$vifGuest comment="Шлюз GUEST" }
    /ip pool
    :if ([:len [find where name="pool-guest"]] = 0) do={ add name=pool-guest ranges=$poolGuest comment="Пул GUEST" } else={ set [find where name="pool-guest"] ranges=$poolGuest }
    /ip dhcp-server
    :if ([:len [find where name="dhcp-guest"]] = 0) do={ add name=dhcp-guest interface=$vifGuest address-pool=pool-guest lease-time=$leaseGuest disabled=no comment="DHCP GUEST" } else={ set [find where name="dhcp-guest"] interface=$vifGuest address-pool=pool-guest lease-time=$leaseGuest disabled=no }
    /ip dhcp-server network
    :if ([:len [find where address=$netGuest]] = 0) do={ add address=$netGuest gateway=$gwGuest dns-server=$gwGuest comment="Мережа GUEST" } else={ set [find where address=$netGuest] gateway=$gwGuest dns-server=$gwGuest }
}

:if ($enableIot = true) do={
    /ip address
    :if ([:len [find where interface=$vifIot and address=$ipIot]] = 0) do={ add address=$ipIot interface=$vifIot comment="Шлюз IOT" }
    /ip pool
    :if ([:len [find where name="pool-iot"]] = 0) do={ add name=pool-iot ranges=$poolIot comment="Пул IOT" } else={ set [find where name="pool-iot"] ranges=$poolIot }
    /ip dhcp-server
    :if ([:len [find where name="dhcp-iot"]] = 0) do={ add name=dhcp-iot interface=$vifIot address-pool=pool-iot lease-time=$leaseIot disabled=no comment="DHCP IOT" } else={ set [find where name="dhcp-iot"] interface=$vifIot address-pool=pool-iot lease-time=$leaseIot disabled=no }
    /ip dhcp-server network
    :if ([:len [find where address=$netIot]] = 0) do={ add address=$netIot gateway=$gwIot dns-server=$gwIot comment="Мережа IOT" } else={ set [find where address=$netIot] gateway=$gwIot dns-server=$gwIot }
}

# =============================================================================
# 7. DNS
# =============================================================================

/ip dns set servers=$dnsUpstream allow-remote-requests=yes max-udp-packet-size=512 cache-size=2048KiB

# =============================================================================
# 8. FIREWALL
# =============================================================================

# Для WAN-адміністрування довірені адреси пропускаються ДО bruteforce.
# Це не дає власним IP потрапити до динамічного blacklist.
# src-address у firewall приймає лише одне значення — список довірених
# адрес розгортається в окреме правило на кожен IP/CIDR.
:local wanAdminAddr ""
:if ($enableWanSsh = true) do={
    :foreach wanAdminAddr in=[:toarray $wanAdminAddresses] do={
        /ip firewall filter add chain=input action=accept protocol=tcp dst-port=22 \
            src-address=$wanAdminAddr in-interface-list=WAN comment="WAN admin: SSH з довірених IP"
    }
}
:if ($enableWanWinbox = true) do={
    :foreach wanAdminAddr in=[:toarray $wanAdminAddresses] do={
        /ip firewall filter add chain=input action=accept protocol=tcp dst-port=$routerWinboxPort \
            src-address=$wanAdminAddr in-interface-list=WAN comment="WAN admin: Winbox з довірених IP"
    }
}

/ip firewall filter
# Bruteforce: правила застосовуються лише до WAN і розміщені перед established.
:if ($enableBruteforce = true) do={
    add chain=input action=drop protocol=tcp dst-port=$bfPorts src-address-list=bf_blacklist \
        in-interface-list=WAN comment="BF: drop з чорного списку"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        src-address-list=bf_stage2 in-interface-list=WAN address-list=bf_blacklist \
        address-list-timeout=$bfBlacklistTime comment="BF: stage2 -> blacklist"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        src-address-list=bf_stage1 in-interface-list=WAN address-list=bf_stage2 \
        address-list-timeout=$bfStageTimeout comment="BF: stage1 -> stage2"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        in-interface-list=WAN address-list=bf_stage1 address-list-timeout=$bfStageTimeout \
        comment="BF: перший пакет -> stage1"
}

add chain=input action=accept connection-state=established,related comment="Input: established,related"
add chain=input action=drop connection-state=invalid comment="Input: invalid"
add chain=input action=accept protocol=icmp icmp-options=3:0-255 comment="Input: PMTU"
add chain=input action=accept protocol=icmp icmp-options=0:0-255 limit=10,5:packet comment="Input: echo-reply"

:if ($wgEndpointMode != "disabled") do={
    add chain=input action=accept protocol=udp dst-port=$wgPort in-interface-list=WAN comment="Input: WireGuard з WAN"
}

add chain=input action=accept in-interface-list=LAN comment="Input: повний доступ з LAN"

:if ($enableGuest = true) do={
    add chain=input action=accept protocol=udp dst-port=53 in-interface-list=GUEST comment="Input: DNS GUEST"
    add chain=input action=accept protocol=udp dst-port=67-68 in-interface-list=GUEST comment="Input: DHCP GUEST"
    add chain=input action=drop in-interface-list=GUEST comment="Input: GUEST не має доступу до роутера"
}
:if ($enableIot = true) do={
    add chain=input action=accept protocol=udp dst-port=53 in-interface-list=IOT comment="Input: DNS IOT"
    add chain=input action=accept protocol=udp dst-port=67-68 in-interface-list=IOT comment="Input: DHCP IOT"
    add chain=input action=drop in-interface-list=IOT comment="Input: IOT не має доступу до роутера"
}

add chain=input action=drop in-interface-list=WAN log=yes log-prefix="fw-in-drop" comment="Input: решту з WAN відкинути"
add chain=input action=drop log=yes log-prefix="fw-in-drop" comment="Input: типове відкидання"

# FORWARD
add chain=forward action=accept connection-state=established,related comment="Forward: established,related"
add chain=forward action=drop connection-state=invalid comment="Forward: invalid"

:if ($enableGuest = true) do={
    add chain=forward action=drop src-address=$netGuest dst-address=$netLan comment="Forward: GUEST -> LAN заблоковано"
    :if ($enableIot = true) do={ add chain=forward action=drop src-address=$netGuest dst-address=$netIot comment="Forward: GUEST -> IOT заблоковано" }
    :if ($wgEndpointMode != "disabled") do={ add chain=forward action=drop src-address=$netGuest dst-address=$wgNet comment="Forward: GUEST -> VPN заблоковано" }
}
:if ($enableIot = true) do={
    add chain=forward action=drop src-address=$netIot dst-address=$netLan comment="Forward: IOT -> LAN заблоковано"
    :if ($enableGuest = true) do={ add chain=forward action=drop src-address=$netIot dst-address=$netGuest comment="Forward: IOT -> GUEST заблоковано" }
    :if ($wgEndpointMode != "disabled") do={ add chain=forward action=drop src-address=$netIot dst-address=$wgNet comment="Forward: IOT -> VPN заблоковано" }
    add chain=forward action=accept src-address=$netLan dst-address=$netIot comment="Forward: LAN -> IOT дозволено"
}

add chain=forward action=accept in-interface-list=LAN comment="Forward: LAN назовні"
:if ($enableGuest = true) do={ add chain=forward action=accept in-interface-list=GUEST comment="Forward: GUEST назовні" }
:if ($enableIot = true) do={ add chain=forward action=accept in-interface-list=IOT comment="Forward: IOT назовні" }
add chain=forward action=drop in-interface-list=WAN log=yes log-prefix="fw-fwd-drop" comment="Forward: не dstnat-трафік з WAN"
add chain=forward action=drop log=yes log-prefix="fw-fwd-drop" comment="Forward: типове відкидання"

# NAT і захист від SYN flood — шлях RouterOS /ip settings (connection tracking
# tcp-syn-cookie вважається застарілим, як і в основному профілі).
/ip settings set tcp-syncookies=yes
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN comment="NAT: локальні мережі в інтернет"

/ip firewall raw
add chain=prerouting action=drop protocol=udp dst-port=53 in-interface-list=WAN comment="RAW: DNS-router не назовні"
# src-address у firewall приймає лише одне значення — список через кому
# не підтримується, тому кожен приватний префікс додається окремим правилом.
:local spoofNet ""
:foreach spoofNet in={"10.0.0.0/8";"172.16.0.0/12";"192.168.0.0/16";"100.64.0.0/10";"127.0.0.0/8"} do={
    /ip firewall raw add chain=prerouting action=drop src-address=$spoofNet in-interface-list=WAN comment="RAW: анти-спуфінг приватних джерел"
}

# =============================================================================
# 8а. СЛУЖБИ АДМІНІСТРУВАННЯ
# =============================================================================

/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set api disabled=yes
:do { set www-ssl disabled=yes } on-error={}
:do { set api-ssl disabled=yes } on-error={}
:do { set btest-server disabled=yes } on-error={}

# Цільова версія RouterOS >= 7.20, тому available-from застосовується напряму.
# Списки джерел: LAN завжди; wgNet — лише коли WireGuard створюється та
# відповідний тумблер дозволяє доступ через тунель. Довірені WAN-адреси
# додаються для відповідної служби; firewall також має окремі allow-правила.
:local sshNets $netLan
:local winboxNets $netLan
:if ($wgEndpointMode != "disabled") do={
    :if ($enableWgSsh = true) do={:set sshNets ($sshNets . "," . $wgNet)}
    :if ($enableWgWinbox = true) do={:set winboxNets ($winboxNets . "," . $wgNet)}
}
:if ($enableWanSsh = true) do={
    set ssh port=$routerSshPort available-from=($sshNets . "," . $wanAdminAddresses)
} else={
    set ssh port=$routerSshPort available-from=$sshNets
}
:if ($enableWanWinbox = true) do={
    set winbox port=$routerWinboxPort available-from=($winboxNets . "," . $wanAdminAddresses)
} else={
    set winbox port=$routerWinboxPort available-from=$winboxNets
}

/ip ssh set strong-crypto=yes
# З RouterOS 7.13 SNMP перенесено з /ip snmp на верхній рівень /snmp.
/snmp set enabled=no

/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN
/ip upnp set enabled=no

# =============================================================================
# 9. WIREGUARD VPN — КЕРУЄТЬСЯ wgEndpointMode
# =============================================================================

:if ($wgEndpointMode != "disabled") do={
    :if ([:len [/interface wireguard find where name="wg-vpn"]] = 0) do={
        /interface wireguard add name=wg-vpn listen-port=$wgPort mtu=1420 comment="WireGuard VPN"
    }
    :if ([:len [/ip address find where interface="wg-vpn" and address=$wgAddr]] = 0) do={
        /ip address add address=$wgAddr interface=wg-vpn comment="Шлюз WireGuard"
    }
    :if ([:len [/interface wireguard peers find where interface="wg-vpn" and allowed-address=$wgPeerAddr]] = 0) do={
        /interface wireguard peers add interface=wg-vpn public-key=$wgPeerKey allowed-address=$wgPeerAddr comment="Клієнт №1"
    }
    :if ([:len [/interface list member find where interface="wg-vpn" and list="LAN"]] = 0) do={
        /interface list member add interface=wg-vpn list=LAN
    }
    :if ($wgEndpointMode = "mikrotik-ddns") do={
        /ip cloud set ddns-enabled=yes update-time=yes
    }
}

# Для wgEndpointMode=ip клієнтський Endpoint: wgEndpointIp:wgPort.
# Для wgEndpointMode=mikrotik-ddns використовуйте dns-name з /ip cloud print.
# Публічний ключ роутера: /interface wireguard print detail
# Приватний ключ клієнта зберігається лише на клієнтському пристрої.

# =============================================================================
# 10. QoS — ОПЦІЙНО
# =============================================================================

# /queue simple add name=limit-guest target=$netGuest max-limit=10M/10M comment="Обмеження швидкості GUEST"

# =============================================================================
# 11. ЗАВЕРШЕННЯ ТА МАРКЕР УСПІШНОГО ІМПОРТУ
# =============================================================================

/system note set show-at-login=yes note="CONFIG OK — import finished. Authorization required. Unauthorized access is prohibited."
