# ============================================================================
# Налаштування WireGuard (СЕРВЕР) для MikroTik — RouterOS v7
# Сценарій: віддалений доступ (road warrior).
# Телефон / ноутбук підключається ззовні та отримує доступ до LAN
# і (за бажанням) вихід в інтернет через цей роутер.
#
# ВИМОГИ:
#   - RouterOS v7.0 або новіша (у v6 WireGuard відсутній);
#   - наявні інтерфейс-листи WAN та LAN (див. mikrotik_settings / firewall_V2);
#   - порт UDP $wgPort має бути вільний і не зайнятий іншим сервісом.
#
# ЯК ЗАСТОСУВАТИ:
#   1. Заповніть змінні у блоці «ЗМІННІ» нижче.
#   2. Виконайте скрипт у терміналі (SSH) або через Winbox:
#      /import file-name=wireguard_server.rsc
#   3. Скопіюйте публічний ключ сервера (скрипт покаже його в логері).
#   4. Занесіть публічний ключ КЛІЄНТА у змінну $peerPubKey
#      та запустіть блок «ДОДАВАННЯ ПІРА» повторно (idempotent).
#
# ВАЖЛИВО: правило firewall для UDP-порта додається ПЕРЕД правилом
# «Drop excessive UDP flood» (анти-флуд), інакше пакети WireGuard
# більше 500 байт будуть відкидатися і тунель «зависне».
# ============================================================================

# --------------------------- ЗМІННІ (редагуйте тут) -------------------------

# Назва WireGuard-інтерфейсу на роутері
:local wgName "wg-remote"

# UDP-порт, який слухає WireGuard (приховуйте від сканерів: не стандартний 13231)
:local wgPort 51820

# MTU тунелю (1420 — безпечне значення для більшості провайдерів)
:local wgMtu 1420

# Підмережа тунелю (використовуйте унікальну мережу, не таку як LAN)
:local tunnelSubnet "10.66.66.0/24"

# IP-адреса роутера всередині тунелю (клієнти використовують її як gateway/DNS)
:local tunnelIp "10.66.66.1/24"

# DNS-сервер, який отримають клієнти (IP роутера в тунелі)
:local clientDns "10.66.66.1"

# Назва першого піра (клієнта) — для зручності в списку
:local peerName "phone-roman"

# ПУБЛІЧНИЙ ключ клієнта (згенерований НА КЛІЄНТІ: wg genkey | tee privatekey | wg pubkey > publickey)
# Поки пусто — пір не буде додано. Заповніть і перезапустіть блок «ДОДАВАННЯ ПІРА».
:local peerPubKey ""

# Дозволені IP для піра: адреса клієнта в тунелі /32
# Кожному піру — СВОЯ унікальна адреса з діапазону $tunnelSubnet!
:local peerAllowedIp "10.66.66.2/32"

# Підмережа локальної мережі (LAN) — для обмеження доступу клієнтів тунелю
:local lanSubnet "192.168.88.0/24"

# Чи дозволяти клієнтам вихід в інтернет через цей роутер (yes/no)
:local allowInternet "yes"

# ----------------------------------------------------------------------------

# --------------------------- СТВОРЕННЯ ІНТЕРФЕЙСУ ---------------------------

# Створюємо інтерфейс лише якщо його ще немає (безпечний повторний запуск).
# Пара ключів (private/public) генерується RouterOS автоматично.
:if ([:len [/interface/wireguard find name=$wgName]] = 0) do={
    /interface/wireguard add name=$wgName listen-port=$wgPort mtu=$wgMtu \
        comment="wireguard_server"
    :log info ("WireGuard: створено інтерфейс " . $wgName)
} else={
    :log warning ("WireGuard: інтерфейс " . $wgName . " вже існує — пропускаю")
}

# Призначаємо IP-адресу тунелю (якщо її ще немає)
:if ([:len [/ip/address find where address=$tunnelIp]] = 0) do={
    /ip/address add address=$tunnelIp interface=$wgName comment="wireguard_tunnel_ip"
}

# Додаємо WireGuard-інтерфейс до списку LAN:
# клієнти тунелю отримують ті самі правила, що й локальна мережа
:if ([:len [/interface/list/member find where interface=$wgName]] = 0) do={
    /interface/list/member add list=LAN interface=$wgName comment="wireguard_in_LAN"
}

# Показуємо публічний ключ сервера — його треба вписати в конфіг клієнта
:local serverPubKey [/interface/wireguard get [find name=$wgName] public-key]
:log info ("WireGuard PUBLIC KEY сервера (для клієнта): " . $serverPubKey)
# Дублюємо в термінал для зручності
:put ("WireGuard PUBLIC KEY сервера (для клієнта): " . $serverPubKey)

# ----------------------------- ДОДАВАННЯ ПІРА -------------------------------

# Додаємо клієнта, тільки якщо вказано його публічний ключ
:if ([:len $peerPubKey] > 0) do={
    # Захист від дублікатів: пір із таким ключем уже існує?
    :if ([:len [/interface/wireguard/peers find where interface=$wgName public-key=$peerPubKey]] = 0) do={
        /interface/wireguard/peers add interface=$wgName name=$peerName \
            public-key=$peerPubKey allowed-address=$peerAllowedIp \
            comment="wireguard_peer"
        :log info ("WireGuard: додано піра " . $peerName)
    } else={
        :log warning ("WireGuard: пір " . $peerName . " уже існує — пропускаю")
    }
} else={
    :log warning "WireGuard: peerPubKey порожній — пір не додано (заповніть змінну та перезапустіть скрипт)"
}

# ------------------------------- FIREWALL -----------------------------------

/ip/firewall/filter

# Дозволяємо вхідні UDP-пакети WireGuard на WAN.
# place-before: ставимо ПЕРЕД правилом «Drop excessive UDP flood»,
# інакше анти-флуд відкидасть пакети >500 байт і тунель не працюватиме.
:if ([:len [/ip/firewall/filter find where comment="Allow WireGuard input"]] = 0) do={
    :do {
        add chain=input action=accept protocol=udp dst-port=$wgPort \
            in-interface-list=WAN comment="Allow WireGuard input" \
            place-before=[find comment="Drop excessive UDP flood"]
    } on-error={
        # Правило флуду не знайдено — ставимо принаймні ПЕРЕД «Drop all from WAN»
        :do {
            add chain=input action=accept protocol=udp dst-port=$wgPort \
                in-interface-list=WAN comment="Allow WireGuard input" \
                place-before=[find comment="Drop all from WAN"]
        } on-error={
            # Ні флуд-правила, ні блокування WAN не знайдено —
            # не додаємо «нікуди» тихо, а зупиняємось із явною помилкою
            :error "WireGuard: не знайдено блокуючих правил input — додайте правило accept udp dst-port=$wgPort вручну ПЕРЕД drop-правилами"
        }
    }
}

# Дозволяємо нові з'єднання З тунелю ДО локальної мережі (dst-address обмежує
# доступ саме LAN; інтернет клієнтам дає правило LAN->WAN + NAT нижче)
:if ([:len [/ip/firewall/filter find where chain=forward comment="Allow WireGuard to LAN"]] = 0) do={
    add chain=forward action=accept connection-state=new in-interface=$wgName \
        dst-address=$lanSubnet comment="Allow WireGuard to LAN"
}

# --------------------------- NAT (інтернет клієнтам) ------------------------

/ip/firewall/nat
# Клієнти тунелю ходять в інтернет через WAN-інтерфейс (masquerade).
# Якщо інтернет через VPN не потрібен — закоментуйте правило
# і вимкніть allowInternet.
:if ($allowInternet = "yes") do={
    :if ([:len [/ip/firewall/nat find where comment="WireGuard masquerade"]] = 0) do={
        add chain=srcnat action=masquerade src-address=$tunnelSubnet \
            out-interface-list=WAN comment="WireGuard masquerade"
    }
}

# ------------------------------ ПІДСУМОК ------------------------------------

:log info ("WireGuard: налаштування завершено. Інтерфейс=" . $wgName . \
    " порт=" . $wgPort . " тунель=" . $tunnelSubnet)

# ============================================================================
# ПРИКЛАД КОНФІГУ КЛІЄНТА (файл wg0.conf на ПК / застосунок WireGuard):
#
# [Interface]
# PrivateKey = <приватний_ключ_клієнта>        # згенерований на клієнті
# Address    = 10.66.66.2/32                   # = peerAllowedIp
# DNS        = 10.66.66.1                      # = clientDns
#
# [Peer]
# PublicKey  = <публічний_ключ_сервера>        # скрипт вивів його у :put / лог
# Endpoint   = <публічний_IP_або_DDNS_роутера>:51820
# AllowedIPs = 10.66.66.0/24, 192.168.88.0/24  # тунель + LAN за потреби
#              (0.0.0.0/0 — весь трафік через VPN)
# PersistentKeepalive = 25                      # для мобільних мереж / NAT
#
# ЩОБ ДОДАТИ НОВОГО КЛІЄНТА:
#   1. Згенеруйте на клієнті нову пару ключів.
#   2. Змініть $peerName / $peerPubKey / $peerAllowedIp (.3/32, .4/32 ...).
#   3. Перезапустіть скрипт — існуючі правила не продублюються.
#
# ПЕРЕВІРКА:
#   /interface/wireguard/peers print          — статус пірів (last-handshake)
#   /log print where message~"WireGuard"      — повідомлення скрипта
# ============================================================================
