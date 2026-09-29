/ip firewall address-list add list=trusted_admins address=192.168.88.11 comment="Admin PC"

/ip firewall filter
# Добавляем новое правило в самое начало (position 0)
add action=accept chain=input src-address-list=trusted_admins protocol=tcp dst-port=2240,2241,48291 comment="Accept trusted Admin PC hosts"

# ----------------- 🔥 INPUT CHAIN (Захист самого роутера) -----------------
# 1️⃣ Блокуємо всі пошкоджені та неправильні пакети (ефективно відкидає "сміття")
add action=drop chain=input connection-state=invalid comment="Drop invalid packets"

# 2️⃣ Дозволяємо вже встановлені з'єднання (мінімізація навантаження на CPU)
add action=accept chain=input connection-state=established,related comment="Accept established, related connections"

# 3️⃣ Дозволяємо ICMP (ping, traceroute)
add action=accept chain=input protocol=icmp comment="Allow ICMP (ping, traceroute)"

# ----------------- 🛡 АНТИ-БРУТФОРС (SSH, WinBox) -----------------
add action=drop chain=input src-address-list=brute_force_stage3 protocol=tcp dst-port=2240,2241,48291 comment="Block brute force SSH & WinBox"
add action=add-src-to-address-list chain=input src-address-list=brute_force_stage2 protocol=tcp dst-port=2240,2241,48291 connection-state=new address-list=brute_force_stage3 address-list-timeout=10d comment="Move to stage 3"
add action=add-src-to-address-list chain=input src-address-list=brute_force_stage1 protocol=tcp dst-port=2240,2241,48291 connection-state=new address-list=brute_force_stage2 address-list-timeout=10m comment="Move to stage 2"
add action=add-src-to-address-list chain=input protocol=tcp dst-port=2240,2241,48291 connection-state=new address-list=brute_force_stage1 address-list-timeout=1m comment="Start brute-force tracking"

# ----------------- 🛡 АНТИ-ФЛУД (SYN Flood, UDP Flood) -----------------
add action=accept chain=input protocol=tcp tcp-flags=syn connection-state=new limit=50,5:packet comment="Allow limited new connections"
add action=drop chain=input protocol=tcp tcp-flags=syn connection-state=new comment="Drop excessive SYN flood"

add action=accept chain=input protocol=udp packet-size=0-500 limit=200,5:packet comment="Allow limited UDP traffic"
add action=drop chain=input protocol=udp comment="Drop excessive UDP flood"

# ----------------- 🛡 ЗАХИСТ ВІД СКАНУВАННЯ -----------------
add action=add-src-to-address-list chain=input protocol=tcp psd=21,3s,3,1 address-list=port_scanners address-list-timeout=2h comment="Detect port scanners"
add action=drop chain=input src-address-list=port_scanners comment="Drop known port scanners"

# ----------------- 🌍 ГЕОФІЛЬТР (БЛОК НЕ УКРАЇНСЬКИХ IP) -----------------
# add action=drop chain=input src-address-list=!allowed_countries dst-port=22,8291 comment="Block SSH & WinBox from foreign countries"

# ----------------- 🔥 БЛОКУЄМО ВСІ НЕВІДПОВІДНІ ПІДКЛЮЧЕННЯ -----------------
add action=drop chain=input connection-nat-state=!dstnat in-interface-list=WAN comment="Drop all from WAN"

# ----------------- 🚀 FASTTRACK (Оптимізація швидкості) -----------------
/ip firewall mangle
add action=mark-connection chain=forward connection-state=established,related new-connection-mark=fasttrack_conn passthrough=no
/ip firewall filter
add action=fasttrack-connection chain=forward connection-mark=fasttrack_conn comment="Enable FastTrack"

# ----------------- 🔥 FORWARD CHAIN (Захист проходячого трафіку) -----------------
# 1️⃣ Блокуємо invalid-з'єднання (захист від фрагментованих атак)
add action=drop chain=forward connection-state=invalid comment="Drop invalid packets"

# 2️⃣ Дозволяємо вже встановлені сесії (зменшує навантаження)
add action=accept chain=forward connection-state=established,related comment="Accept established, related connections"

# 3️⃣ Дозволяємо трафік з LAN у WAN
add action=accept chain=forward in-interface-list=LAN out-interface-list=WAN comment="Allow LAN to WAN"

# 4️⃣ Захищаємо від сканування
add action=add-src-to-address-list chain=forward protocol=tcp psd=21,3s,3,1 address-list=port_scanners address-list-timeout=2h comment="Detect port scanners"
add action=drop chain=forward src-address-list=port_scanners comment="Drop known port scanners"

# 5️⃣ Лімітуємо одночасні підключення (анти-DDoS)
add action=drop chain=forward protocol=tcp connection-limit=100,32 comment="Limit simultaneous TCP connections per IP"

# 6️⃣ Блокуємо доступ до внутрішніх IP з WAN
# add action=drop chain=forward in-interface-list=WAN dst-address=192.168.0.0/16 comment="Block access to private IP ranges"
# add action=drop chain=forward in-interface-list=WAN dst-address=10.0.0.0/8 comment="Block access to private IP ranges"
# add action=drop chain=forward in-interface-list=WAN dst-address=172.16.0.0/12 comment="Block access to private IP ranges"

# 7️⃣ Відкидаємо весь інший трафік із WAN (крім дозволеного NAT)
add action=drop chain=forward connection-nat-state=!dstnat in-interface-list=WAN comment="Drop all unknown traffic from WAN"

# ----------------- 🔥 NAT-ПРАВИЛА (DNS Redirect) -----------------
/ip firewall nat
add chain=dstnat in-interface-list=LAN protocol=udp dst-port=53 action=redirect comment="Redirect LAN DNS UDP"
add chain=dstnat in-interface-list=LAN protocol=tcp dst-port=53 action=redirect comment="Redirect LAN DNS TCP"

# ----------------- 🚧 ВИМКНЕННЯ НЕПОТРІБНИХ СЕРВІСІВ -----------------
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set api disabled=yes
set api-ssl disabled=yes

# ----------------- 🌍 ОБМЕЖЕННЯ ВИЯВЛЕННЯ МЕРЕЖІ -----------------
/ip neighbor discovery-settings
set discover-interface-list=LAN
