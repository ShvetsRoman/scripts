# =============================================================================
#  MikroTik hAP ac² (D53G-5HacD2HnT-TC&FB) — КОНФІГУРАЦІЯ
#  RouterOS:  7.16+   |   Файл читається скриптом setup.sh
# =============================================================================
#
#  ОСОБЛИВОСТІ МОДЕЛІ:
#   - WiFi на чипі QCA4019 (802.11ac wave2) → використовується пакет "wifi"
#     (мінімум RouterOS 7.13, до 7.13 називався "wifiwave2").
#   - Основні радіомодулі: wifi1 = 5 ГГц, wifi2 = 2.4 ГГц.
#   - Віртуальні AP (guest/IoT) створюються через parent= (потрібен ≥ 7.16).
#
#  ЗАСТОСУВАННЯ:
#    ./setup.sh --name hap-ac2           # завантажити файл (без застосування)
#    ./setup.sh --name hap-ac2 --reset   # завантажити + reset + автозастосування
#  ВРУЧНУ (після завантаження):
#    /import file-name=config.rsc
#
#  УВАГА: рядки :global НЕ мають коментарів у кінці — їх парсить setup.sh.
#
# =============================================================================


# =============================================================================
# 0. ЗМІННІ — ВСІ НАЛАШТУВАННЯ В ОДНОМУ МІСЦІ
# =============================================================================

# --- Підключення (використовує setup.sh для SSH/SFTP) ---
:global routerHost "192.168.88.1"
:global routerUser "admin-lb"
:global routerPassword ""
:global routerSshPort 22
:global configFile "config.rsc"

# --- Система ---
:global routerIdentity "hap-ac2-home"
:global TIMEZONE "Europe/Kyiv"
:global ntpServer1 "ua.pool.ntp.org"
:global ntpServer2 "time.cloudflare.com"
:global adminUser "admin-lb"
:global adminPassword "ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА"

# --- Тумблери (true/false) ---
:global enableWireguard true
:global enableGuest true
:global enableIot true
:global enableWifi2Ghz true
:global enableWifi5Ghz true

# --- Мережа ---
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

# --- WiFi (пакет "wifi": wifi1 = 5 ГГц, wifi2 = 2.4 ГГц) ---
:global wifiSsid "Home-WiFi"
:global wifiPassword "ЗАМІНІТЬ_ПАРОЛЬ_WIFI"
:global guestSsid "Home-Guest"
:global guestPassword "ЗАМІНІТЬ_ПАРОЛЬ_ГОСТЯ"
:global iotSsid "Home-IoT"
:global iotPassword "ЗАМІНІТЬ_ПАРОЛЬ_IOT"

# --- WireGuard ---
:global wgPort 13231
:global wgAddr "10.10.100.1/24"
:global wgNet "10.10.100.0/24"
:global wgPeerAddr "10.10.100.2/32"
:global wgPeerKey "ЗАМІНІТЬ_КЛЮЧ_WG"

# --- Службові ---
:global backupStartTime "03:00:00"

# --- Захист від брутфорсу ---
# bfPorts — порти для захисту (мують відповідати /ip service:
# тут ssh=22 та winbox=8291). Захист діє ТІЛЬКИ на трафік з WAN —
# клієнти LAN (в т.ч. WiFi wlan) ніколи не потрапляють у списки.
:global enableBruteforce true
:global bfPorts "22,8291"
:global bfStageTimeout "1m"
:global bfBlacklistTime "10d"

# --- Бекап та нічний LED ---
:global enableBackup true
:global enableNightLed false
:global nightLedInterval "23:00-07:00"


# =============================================================================
# 1. БАЗОВІ СИСТЕМНІ НАЛАШТУВАННЯ
# =============================================================================

/system identity set name=$routerIdentity

# Часовий пояс і час (потрібні для логів і планувальника)
/system clock set time-zone-name=$TIMEZONE

# Синхронізація часу через NTP
/system ntp client set enabled=yes
/system ntp client servers add address=$ntpServer1
/system ntp client servers add address=$ntpServer2

# Логування помилок на диск (зберігається між перезавантаженнями)
# Ідемпотентно: спочатку прибрати наші дію/правило, якщо вони вже є
# (важливо при повторному імпорті поверх наявного конфігу)
/system logging action remove [find where name="diskLog"]
/system logging remove [find where action="diskLog"]
/system logging action add name=diskLog target=disk disk-file-name=routerlog disk-lines-per-file=1000
/system logging add topics=error,warning,critical action=diskLog

/system note set show-at-login=yes note="Authorization required. Unauthorized access is prohibited."


# =============================================================================
# 2. КОРИСТУВАЧІ ТА БЕЗПЕКА АДМІНІСТРУВАННЯ
# =============================================================================

/user add name=$adminUser group=full password=$adminPassword comment="Основний адміністратор"

# Вимикаємо дефолтного "admin" (тільки якщо основний не називається "admin")
:if ($adminUser != "admin") do={ /user disable admin }


# =============================================================================
# 3. ІНТЕРФЕЙСИ, BRIDGE ТА VLAN
# =============================================================================

# Міст з фільтрацією VLAN — "хребет" локальної мережі
/interface bridge add name=$bridgeName vlan-filtering=yes protocol-mode=rstp comment="Основний міст LAN"

# LAN-порти; pvid = VLAN для нетегованого трафіку порту
:foreach p in=$lanPorts do={
    /interface bridge port add bridge=$bridgeName interface=$p pvid=$vlanLan comment="LAN-порт"
}

# VLAN-інтерфейси на мосту — "віртуальні роутери" кожної мережі
/interface vlan add name=$vifLan vlan-id=$vlanLan interface=$bridgeName comment="Основна мережа"

# Гостьова/IoT — лише за тумблерами
:if ($enableGuest = true) do={
    /interface vlan add name=$vifGuest vlan-id=$vlanGuest interface=$bridgeName comment="Гостьова мережа"
}
:if ($enableIot = true) do={
    /interface vlan add name=$vifIot vlan-id=$vlanIot interface=$bridgeName comment="Мережа IoT"
}

# Теговані VLAN на самому мосту.
# Для пакету "wifi" гостьовий/IoT SSID тегує трафік САМ (datapath.vlan-id),
# тому wifi1/wifi2 мають бути тегованими членами VLAN 20/30.
# Радіо може бути вимкнене тумблером — інтерфейс все одно існує, членство не шкодить.
# На платформах без WiFi (наприклад, CHR у VirtualBox) радіо-члени пропускаються.
/interface bridge vlan add bridge=$bridgeName tagged=$bridgeName vlan-ids=$vlanLan
:if ($enableGuest = true) do={
    /interface bridge vlan add bridge=$bridgeName tagged=$bridgeName,wifi1,wifi2 vlan-ids=$vlanGuest
}
:if ($enableIot = true) do={
    /interface bridge vlan add bridge=$bridgeName tagged=$bridgeName,wifi2 vlan-ids=$vlanIot
}


# =============================================================================
# 3а. СПИСКИ ІНТЕРФЕЙСІВ (створюються ДО firewall)
# =============================================================================

# WAN та LAN існують завжди
/interface list add name=WAN
/interface list add name=LAN

/interface list member add interface=$wanInterface list=WAN
/interface list member add interface=$vifLan list=LAN

# Гостьова/IoT — лише за тумблерами
:if ($enableGuest = true) do={
    /interface list add name=GUEST
    /interface list member add interface=$vifGuest list=GUEST
}
:if ($enableIot = true) do={
    /interface list add name=IOT
    /interface list member add interface=$vifIot list=IOT
}

# WireGuard додається до LAN у розділі 9 (після створення wg-vpn)


# =============================================================================
# 4. WiFi (пакет "wifi" — hAP ac²)
# =============================================================================

# Розділ виконується завжди; радіо керується ЛИШЕ тумблерами
# enableWifi2Ghz / enableWifi5Ghz (вимкнення = disabled=yes, не видалення).
# УВАГА: конфіг придатний лише для пристроїв із WiFi-пакетом (RouterOS
# валідує шляхи команд при парсингу). Для CHR без радіо — профіль vbox-test.

# --- Профіль безпеки основної мережі (створюється завжди) ---
# WPA2+WPA3 (SAE) — wave2-чип підтримує змішаний режим
/interface wifi security add \
    name=sec-home \
    authentication-types=wpa2-psk,wpa3-psk \
    passphrase=$wifiPassword \
    disable-pmkid=yes \
    comment="Безпека основного WiFi"

# --- Конфігурація основного SSID (створюється завжди) ---
# Без datapath → трафік нетегований, потрапляє у VLAN через pvid порту
/interface wifi configuration add \
    name=cfg-home \
    ssid=$wifiSsid \
    security=sec-home \
    comment="Основний SSID"

# --- Радіо 5 ГГц (wifi1) — за тумблером ---
:if ($enableWifi5Ghz = true) do={
    # QCA4019: 802.11ac wave2; 802.11ax НЕ підтримується
    /interface wifi set wifi1 \
        configuration=cfg-home \
        channel.band=5ghz-n,5ghz-ac \
        channel.width=20/40/80mhz \
        country=Ukraine \
        comment="5 ГГц основна мережа"
    /interface bridge port add bridge=$bridgeName interface=wifi1 pvid=$vlanLan \
        comment="WiFi 5 основна → VLAN LAN"
} else={
    /interface wifi set wifi1 disabled=yes comment="WiFi 5 ГГц вимкнено тумблером"
}

# --- Радіо 2.4 ГГц (wifi2) — за тумблером ---
:if ($enableWifi2Ghz = true) do={
    /interface wifi set wifi2 \
        configuration=cfg-home \
        channel.band=2ghz-g,2ghz-n \
        channel.width=20/40mhz \
        country=Ukraine \
        comment="2.4 ГГц основна мережа"
    /interface bridge port add bridge=$bridgeName interface=wifi2 pvid=$vlanLan \
        comment="WiFi 2.4 основна → VLAN LAN"
} else={
    /interface wifi set wifi2 disabled=yes comment="WiFi 2.4 ГГц вимкнено тумблером"
}

# --- Гостьова конфігурація + VAP — за тумблерами радіо і мережі ---
:if (($enableGuest = true) and (($enableWifi5Ghz = true) or ($enableWifi2Ghz = true))) do={
    /interface wifi security add \
        name=sec-guest \
        authentication-types=wpa2-psk,wpa3-psk \
        passphrase=$guestPassword \
        disable-pmkid=yes \
        comment="Безпека гостьового WiFi"
    # datapath.vlan-id тегує трафік клієнтів у VLAN GUEST
    /interface wifi configuration add \
        name=cfg-guest \
        ssid=$guestSsid \
        security=sec-guest \
        datapath.vlan-id=$vlanGuest \
        comment="Гостьовий SSID → VLAN GUEST"
}

:if (($enableGuest = true) and ($enableWifi5Ghz = true)) do={
    /interface wifi add name=wifi1-guest parent=wifi1 configuration=cfg-guest disabled=no \
        comment="5 ГГц гостьова мережа"
}

:if (($enableGuest = true) and ($enableWifi2Ghz = true)) do={
    /interface wifi add name=wifi2-guest parent=wifi2 configuration=cfg-guest disabled=no \
        comment="2.4 ГГц гостьова мережа"
}

# --- IoT конфігурація + VAP — за тумблерами радіо і мережі ---
:if (($enableIot = true) and ($enableWifi2Ghz = true)) do={
    /interface wifi security add \
        name=sec-iot \
        authentication-types=wpa2-psk \
        passphrase=$iotPassword \
        disable-pmkid=yes \
        comment="Безпека IoT WiFi (тільки WPA2 — сумісність зі старими IoT-пристроями)"
    /interface wifi configuration add \
        name=cfg-iot \
        ssid=$iotSsid \
        security=sec-iot \
        datapath.vlan-id=$vlanIot \
        comment="IoT SSID → VLAN IOT"
    /interface wifi add name=wifi2-iot parent=wifi2 configuration=cfg-iot disabled=no \
        comment="2.4 ГГц IoT мережа"
}

# Примітка: окремих bridge-портів для wifi*-guest/wifi*-iot не потрібно —
# гостьовий/IoT трафік заходить у міст УЖЕ тегованим через родинське радіо
# (datapath.vlan-id), членство wifi1/wifi2 у VLAN 20/30 — у розділі 3.



# =============================================================================
# 5. WAN (ІНТЕРНЕТ ВІД ПРОВАЙДЕРА, DHCP)
# =============================================================================

# use-peer-dns=no — DNS беремо самі (розділ 7), не від провайдера
# Ідемпотентно: прибрати наявний dhcp-client на WAN (дефолтний або наш з
# попереднього імпорту), інакше "dhcp-client on that interface already exists"
/ip dhcp-client remove [find where interface=$wanInterface]
/ip dhcp-client add \
    interface=$wanInterface \
    add-default-route=yes \
    use-peer-dns=no \
    dhcp-options=hostname,clientid \
    disabled=no \
    comment="DHCP-клієнт від провайдера"


# =============================================================================
# 6. IP-АДРЕСИ ТА DHCP-СЕРВЕРИ
# =============================================================================

/ip address add address=$ipLan interface=$vifLan comment="Шлюз LAN"

:if ($enableGuest = true) do={
    /ip address add address=$ipGuest interface=$vifGuest comment="Шлюз GUEST"
    /ip pool add name=pool-guest ranges=$poolGuest comment="Пул GUEST"
    /ip dhcp-server add name=dhcp-guest interface=$vifGuest address-pool=pool-guest lease-time=$leaseGuest disabled=no comment="DHCP GUEST"
    /ip dhcp-server network add address=$netGuest gateway=$gwGuest dns-server=$gwGuest comment="Мережа GUEST"
}

:if ($enableIot = true) do={
    /ip address add address=$ipIot interface=$vifIot comment="Шлюз IOT"
    /ip pool add name=pool-iot ranges=$poolIot comment="Пул IOT"
    /ip dhcp-server add name=dhcp-iot interface=$vifIot address-pool=pool-iot lease-time=$leaseIot disabled=no comment="DHCP IOT"
    /ip dhcp-server network add address=$netIot gateway=$gwIot dns-server=$gwIot comment="Мережа IOT"
}

# Основна мережа
/ip pool add name=pool-lan ranges=$poolLan comment="Пул LAN"
/ip dhcp-server add name=dhcp-lan interface=$vifLan address-pool=pool-lan lease-time=$leaseLan disabled=no comment="DHCP LAN"
/ip dhcp-server network add address=$netLan gateway=$gwLan dns-server=$gwLan comment="Мережа LAN"

# --- Статичні резервування (приклади — підставте свої MAC) ---
# /ip dhcp-server lease add address=192.168.10.50 mac-address=AA:BB:CC:DD:EE:01 server=dhcp-lan comment="NAS"
# /ip dhcp-server lease add address=192.168.10.51 mac-address=AA:BB:CC:DD:EE:02 server=dhcp-lan comment="Принтер"


# =============================================================================
# 7. DNS
# =============================================================================

# Роутер — кешуючий DNS для локальних мереж.
# Захист від зовнішніх запитів робиться у firewall (розділ 8).
/ip dns set \
    servers=$dnsUpstream \
    allow-remote-requests=yes \
    max-udp-packet-size=512 \
    cache-size=2048KiB

# Локальні імена (приклади)
# /ip dns static add name=nas.home address=192.168.10.50
# /ip dns static add name=router.home address=192.168.10.1


# =============================================================================
# 8. FIREWALL (списки інтерфейсів створені у розділі 3а)
# =============================================================================

# --- INPUT (трафік на сам роутер) ---
/ip firewall filter

# --- Захист від брутфорсу (SSH/Winbox) — за тумблером ---
# Розташовано ПЕРЕД accept established: чорний список має діяти
# негайно, навіть поки живі старі з'єднання джерела (тому БЕЗ
# connection-state=new — drop матчить і established-пакети).
# Схема MikroTik "Bruteforce prevention": кожен TCP-пакет з WAN на
# захищені порти ($bfPorts) крок за кроком підвищує "стадію" джерела:
#   пакет 1 → bf_stage1, пакет 2 → bf_stage2, пакет 3 → bf_blacklist,
#   далі — drop на час $bfBlacklistTime.
# Адміністрування напряму з WAN не передбачене (лише LAN або WireGuard),
# тому швидкий каскад для WAN-джерел безпечний.
# Списки динамічні і самоочищаються за таймаутами ($bfStageTimeout).
# Усі правила мають in-interface-list=WAN — трафік LAN/wlan не обробляється
# і не може потрапити у чорний список.
:if ($enableBruteforce = true) do={
    /ip firewall filter
    add chain=input action=drop protocol=tcp dst-port=$bfPorts \
        src-address-list=bf_blacklist in-interface-list=WAN \
        comment="BF: drop з чорного списку"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        src-address-list=bf_stage2 in-interface-list=WAN \
        address-list=bf_blacklist address-list-timeout=$bfBlacklistTime \
        comment="BF: stage2 → чорний список"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        src-address-list=bf_stage1 in-interface-list=WAN \
        address-list=bf_stage2 address-list-timeout=$bfStageTimeout \
        comment="BF: stage1 → stage2"
    add chain=input action=add-src-to-address-list protocol=tcp dst-port=$bfPorts \
        in-interface-list=WAN \
        address-list=bf_stage1 address-list-timeout=$bfStageTimeout \
        comment="BF: перший пакет → stage1"
}
add chain=input action=accept connection-state=established,related \
    comment="Input: встановлені та пов'язані з'єднання"
add chain=input action=drop connection-state=invalid \
    comment="Input: невалідні пакети"

# SYN-flood-ліміт вилучено: правило з action=drop та limit= матчало
# перші 50 SYN/s (інвертована логіка), а надлишок і так ловив фінальний
# drop з WAN — тож ефективна поведінка (новий TCP з WAN заборонено)
# не змінилася. Захист від SYN-шторму забезпечує tcp-syn-cookie (нижче).

add chain=input action=accept protocol=icmp icmp-options=3:0-255 \
    comment="Input: PMTU fragmentation-needed (без ліміту — важливо для маскараду)"
add chain=input action=accept protocol=icmp icmp-options=0:0-255 limit=10,5:packet \
    comment="Input: echo-reply з обмеженням (вхідні ping з WAN відкидає фінальний drop)"

# WireGuard — за тумблером
:if ($enableWireguard = true) do={
    /ip firewall filter add chain=input action=accept protocol=udp dst-port=$wgPort in-interface-list=WAN \
        comment="Input: WireGuard з WAN"
}

add chain=input action=accept in-interface-list=LAN \
    comment="Input: повний доступ з LAN (Winbox/SSH/DNS)"

# DNS для гостьової/IoT — за тумблерами
:if ($enableGuest = true) do={
    /ip firewall filter add chain=input action=accept protocol=udp dst-port=53 in-interface-list=GUEST \
        comment="Input: DNS для гостьової мережі"
    /ip firewall filter add chain=input action=accept protocol=udp dst-port=67-68 in-interface-list=GUEST \
        comment="Input: DHCP для гостьової мережі"
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=input action=accept protocol=udp dst-port=53 in-interface-list=IOT \
        comment="Input: DNS для IoT-мережі"
    /ip firewall filter add chain=input action=accept protocol=udp dst-port=67-68 in-interface-list=IOT \
        comment="Input: DHCP для IoT-мережі"
}

add chain=input action=drop in-interface-list=WAN log=yes log-prefix="fw-in-drop" \
    comment="Input: ВСЕ решту з WAN відкинути"

:if ($enableGuest = true) do={
    /ip firewall filter add chain=input action=drop in-interface-list=GUEST \
        comment="Input: гостьова не має доступу до роутера (крім DNS)"
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=input action=drop in-interface-list=IOT \
        comment="Input: IoT не має доступу до роутера (крім DNS)"
}

add chain=input action=drop log=yes log-prefix="fw-in-drop" \
    comment="Input: типове відкидання (страховка)"

# --- FORWARD (трафік між мережами) ---
/ip firewall filter
add chain=forward action=accept connection-state=established,related \
    comment="Forward: встановлені та пов'язані з'єднання"
add chain=forward action=drop connection-state=invalid \
    comment="Forward: невалідні пакети"

# Ізоляція: GUEST та IOT не ходять у LAN, але мають інтернет через NAT
:if (($enableGuest = true) and ($enableIot = true)) do={
    /ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$netLan \
        comment="Forward: GUEST → LAN заблоковано"
    /ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$netIot \
        comment="Forward: GUEST → IOT заблоковано"
    /ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$netLan \
        comment="Forward: IOT → LAN заблоковано"
    /ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$netGuest \
        comment="Forward: IOT → GUEST заблоковано"
}
:if (($enableGuest = true) and ($enableIot = false)) do={
    /ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$netLan \
        comment="Forward: GUEST → LAN заблоковано"
}
:if (($enableIot = true) and ($enableGuest = false)) do={
    /ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$netLan \
        comment="Forward: IOT → LAN заблоковано"
}

# Ізоляція GUEST/IOT від VPN-підмережі: без цього accept-правила
# "все з GUEST/IOT назовні" пропускало б трафік у 10.10.100.0/24
# (підключені WireGuard-піри) повз ізоляцію LAN.
:if ($enableWireguard = true) do={
    :if ($enableGuest = true) do={
        /ip firewall filter add chain=forward action=drop src-address=$netGuest dst-address=$wgNet \
            comment="Forward: GUEST → VPN-підмережу заблоковано"
    }
    :if ($enableIot = true) do={
        /ip firewall filter add chain=forward action=drop src-address=$netIot dst-address=$wgNet \
            comment="Forward: IOT → VPN-підмережу заблоковано"
    }
}

:if ($enableGuest = true) do={
    /ip firewall filter add chain=forward action=drop in-interface-list=GUEST dst-address=$gwGuest \
        comment="Forward: GUEST не трогає сам роутер"
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=forward action=drop in-interface-list=IOT dst-address=$gwIot \
        comment="Forward: IOT не трогає сам роутер"
}

# Керування розумними пристроями з основної мережі — дозволено
:if ($enableIot = true) do={
    /ip firewall filter add chain=forward action=accept src-address=$netLan dst-address=$netIot \
        comment="Forward: LAN → IOT дозволено"
}

add chain=forward action=accept in-interface-list=LAN \
    comment="Forward: все з LAN назовні"

:if ($enableGuest = true) do={
    /ip firewall filter add chain=forward action=accept in-interface-list=GUEST \
        comment="Forward: все з GUEST назовні (через NAT)"
}
:if ($enableIot = true) do={
    /ip firewall filter add chain=forward action=accept in-interface-list=IOT \
        comment="Forward: все з IOT назовні (через NAT)"
}

add chain=forward action=drop in-interface-list=WAN log=yes log-prefix="fw-fwd-drop" \
    comment="Forward: не dstnat'нутий трафік з WAN — відкинути"
add chain=forward action=drop log=yes log-prefix="fw-fwd-drop" \
    comment="Forward: типове відкидання (страховка)"

# --- NAT (маскарад — вихід в інтернет) ---
# SYN-cookie: захист від заповнення conntrack-таблиці під час SYN-шторму
/ip firewall connection tracking set tcp-syn-cookie=yes

/ip firewall nat
add chain=srcnat action=masquerade out-interface-list=WAN \
    comment="NAT: маскарад всіх локальних мереж в інтернет"

# --- RAW: не відкривати DNS-router назовні (захист від amplification) ---
/ip firewall raw
add chain=prerouting action=drop protocol=udp dst-port=53 in-interface-list=WAN \
    comment="RAW: DNS-router не назовні"

# Анти-спуфінг: приватні джерела (RFC1918/loopback/CGNAT) не приходять з WAN
add chain=prerouting action=drop \
    src-address=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,127.0.0.0/8 \
    in-interface-list=WAN \
    comment="RAW: спуфінг приватних джерел з WAN"

# --- Служби адміністрування ---
/ip service
# УВАГА: у /ip service немає властивості comment — пояснення тут
# (Telnet/FTP/www/api вимкнено як небезпечні; ssh/winbox — лише для LAN)
set telnet disabled=yes
set ftp    disabled=yes
set www    disabled=yes
set api    disabled=yes
# Явно вимкнено (secure-by-default): :do on-error — на випадок, якщо
# елемент відсутній у /ip service цієї версії RouterOS
:do { set www-ssl disabled=yes } on-error={}
:do { set api-ssl disabled=yes } on-error={}
:do { set btest-server disabled=yes } on-error={}
/ip snmp set enabled=no
# Дубльний захист: служби обмежені самим RouterOS, а не тільки firewall.
# $wgNet дозволяє адміністрування через WireGuard-підмережу.
set ssh    port=22 address=$netLan,$wgNet
set winbox port=8291 address=$netLan,$wgNet

/ip ssh set strong-crypto=yes

# MAC-сервер: лише Winbox по MAC з LAN (порятунок при втраті IP)
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool mac-server ping set enabled=no

# Neighbor discovery: лише з LAN
/ip neighbor discovery-settings set discover-interface-list=LAN

# UPnP вимкнено (пристрої не відкривають порти самовільно)
/ip upnp set enabled=no


# =============================================================================
# 9. WIREGUARD VPN (ВІДДАЛЕНИЙ ДОСТУП) — за тумблером
# =============================================================================

:if ($enableWireguard = true) do={

    # Секретний ключ генерується роутером автоматично при створенні інтерфейсу
    /interface wireguard add name=wg-vpn listen-port=$wgPort mtu=1420 \
        comment="WireGuard VPN для віддаленого доступу"

    /ip address add address=$wgAddr interface=wg-vpn comment="Шлюз WireGuard"

    # Пір (клієнт). wgPeerKey = PUBLIC-ключ клієнта WireGuard.
    /interface wireguard peers add \
        interface=wg-vpn \
        public-key=$wgPeerKey \
        allowed-address=$wgPeerAddr \
        comment="Клієнт №1 (телефон/ноутбук)"

    # Віддалений адмін має права локального
    /interface list member add interface=wg-vpn list=LAN
}

# PUBLIC-ключ роутера (нужен клієнту): /interface wireguard peers print
#
# Приклад конфігу клієнта (tunnel.conf у додатку WireGuard):
#   [Interface]
#   PrivateKey = <приватний ключ клієнта>
#   Address    = 10.10.100.2/32
#   DNS        = 192.168.10.1
#
#   [Peer]
#   PublicKey  = <PUBLIC-ключ роутера>
#   AllowedIPs = 0.0.0.0/0, ::/0
#   Endpoint   = <зовнішня IP або DDNS>:13231
#   PersistentKeepalive = 25

# NAT для VPN-клієнтів в інтернет (опціонально):
# /ip firewall nat add chain=srcnat action=masquerade src-address=10.10.100.0/24 \
#     out-interface-list=WAN comment="NAT для VPN-клієнтів"

# DDNS MikroTik — якщо провайдер не дає статичну IP:
# /ip cloud set ddns-enabled=yes ddns-update-interval=1h


# =============================================================================
# 10. QoS / ОБМЕЖЕННЯ ГЮСТОВОЇ МЕРЕЖІ (ОПЦІОНАЛЬНО)
# =============================================================================

# /queue simple add name=limit-guest target=$netGuest \
#     max-limit=10M/10M comment="Обмеження швидкості гостьової мережі"


# =============================================================================
# 11. СЛУЖБОВІ СКРИПТИ ТА ПЛАНУВАЛЬНИК
# =============================================================================

# Щоденний бекап: .backup (бінарний) та .rsc (текстовий export) — за тумблером
:if ($enableBackup = true) do={
    /system script add name=backup-daily source={
        :local dateStr [/system clock get date]
        :local fname ("backup-" . [/system identity get name] . "-" . $dateStr)
        /system backup save name=$fname
        /export file=$fname show-sensitive
        :log info "Бекап виконано: $fname"
        # Ротація: лишаємо останні 14 файлів (7 пар backup + rsc).
        # УВАГА: порядок /file find залежить від версії RouterOS —
        # звірити на живому роутері перед покладанням на ротацію.
        :local files [/file find where name~"^backup-"]
        :if ([:len $files] > 14) do={
            :for i from=0 to=([:len $files] - 15) do={
                /file remove [:pick $files $i ($i + 1)]
            }
        }
    }

    /system scheduler add name=backup-daily on-event="/system script run backup-daily" \
        start-time=$backupStartTime interval=1d \
        comment="Щоденний бекап"
}

# Watchdog WAN: 3 невдалі пінги поспіль → перезапуск DHCP-клієнта
# /system script add name=wan-watchdog source={
#     :local count 0
#     :for i from=1 to=3 do={
#         :if ([/ping 8.8.8.8 count=1 interface=ether1 as-value] = false) do={
#             :set count ($count + 1)
#         }
#     }
#     :if ($count >= 3) do={
#         :log warning "WAN пропав — перезапускаю DHCP-клієнт"
#         /ip dhcp-client disable [find]
#         :delay 5s
#         /ip dhcp-client enable [find]
#     }
# }
# /system scheduler add name=wan-watchdog on-event="/system script run wan-watchdog" \
#     interval=5m comment="Перевірка WAN кожні 5 хв"


# =============================================================================
# 12. ОПЦІОНАЛЬНЕ
# =============================================================================

# Нічний режим LED — за тумблером (гасить user-led у заданий інтервал).
# Ім'я діоду звірте на своєму пристрої: /system led print
:if ($enableNightLed = true) do={
    /system led add all=yes leds=user-led type=off interval=$nightLedInterval \
        comment="Нічний режим"
}


# =============================================================================
# КІНЕЦЬ КОНФІГУРАЦІЇ
# =============================================================================
#  ПІСЛЯ ЗАСТОСУВАННЯ ПЕРЕВІРТЕ:
#  1. /ip dhcp-client print          — WAN отримав IP від провайдера
#  2. /ip firewall filter print      — правила активні (не disabled)
#  3. /interface wifi print          — WiFi відповідає тумблерам
#  4. /ip dhcp-server lease print    — клієнти отримують адреси
#  5. /ping 8.8.8.8                  — інтернет працює
#  6. (якщо WiFi увімкнено) Клієнт на Home-WiFi → адреса 192.168.10.x
#  7. (якщо WiFi увімкнено) Клієнт на Home-Guest → адреса 192.168.20.x,
#     без доступу до 192.168.10.x
#  8. /system reboot                 — перевірити, що все піднімається з нуля
#  9. Тумблери ENABLE_* у розділі 0 — вимкнене має бути відсутнім:
#     /interface wireguard print; /interface vlan print; /interface list print
# 10. При логіні видно "CONFIG OK — import finished" — конфіг застосувався
#     ПОВНІСТЮ. Якщо банера немає — імпорт обірвався на одному з розділів:
#     доступ лише через MAC-Winbox (див. README, розділ «Відновлення»).
# =============================================================================

# Маркер успішного завершення імпорту (поєднаний з банером входу).
# Тримати ОСТАННІМ рядком конфігу: якщо імпорт обірветься раніше,
# банер з "CONFIG OK" не з'явиться при логіні.
/system note set show-at-login=yes \
    note="CONFIG OK — import finished. Authorization required. Unauthorized access is prohibited."
