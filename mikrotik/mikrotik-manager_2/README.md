# MikroTik Router Manager

Повні конфігурації та скрипт розгортання для домашніх роутерів MikroTik.

## Структура проєкту

```
mikrotik-manager/
├── setup.sh                      # скрипт завантаження конфіга на роутер
├── README.md
└── routers/
    ├── hap-ac/                   # hAP AC (RB962UiGS-5HacT2HnT), пакет "wireless"
    │   └── config.rsc
    ├── hap-ac2/                  # hAP ac² (D53G-5HacD2HnT), пакет "wifi"
    │   └── config.rsc
    ├── hap-ac3/                  # hAP ac³ (RBD53iG-5HacD2HnT), пакет "wifi"
    │   └── config.rsc
    └── vbox-test/                # тестовий профіль: RouterOS CHR у VirtualBox
        └── config.rsc
```

Кожен роутер — окремий каталог з файлом `config.rsc`. Додати новий роутер =
створити каталог `routers/<ім'я>/config.rsc` за зразком наявних.

> ⚠️ **`config.rsc` не комітиться** (правило в `../.gitignore`): після заповнення
> файл містить `adminPassword` / паролі WiFi / ключ WireGuard у відкритому
> вигляді. Зберігайте його локально та в бекапах поза Git; для спільного
> зберігання тримайте шаблон з плейсхолдерами під іншим іменем
> (наприклад, `config.rsc.example`).

## Використання

```bash
# ТІЛЬКИ завантажити config.rsc на роутер (без імпорту)
./setup.sh --name hap-ac

# Завантажити + повний reset no-defaults + автозастосування конфіга
./setup.sh --name hap-ac --reset

# Без підтверджень (для автоматизації)
./setup.sh --name hap-ac --reset --yes

# Пробний прогін (показати дії, нічого не виконувати)
./setup.sh --name hap-ac --reset --dry-run

# SSH-ключ замість пароля
./setup.sh --name hap-ac --reset --key ~/.ssh/id_ed25519
```

### Режими

| Режим | Що робить |
|-------|-----------|
| без `--reset` | **Тільки завантажує** файл на роутер. Застосувати вручну на роутері: `/import file-name=config.rsc` |
| з `--reset` | Завантажує файл, потім `/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=config.rsc`. Роутер перезавантажується і **сам** імпортує конфіг. Орієнтовно 2–3 хв. |

> **Чому reset такий**: після `no-defaults` скидання SSH-адреси попередньої
> конфігурації зникають, тому імпорт можливий лише через `run-after-reset`.

## Змінні

> ⚠️ **Обмеження RouterOS:** у деяких версіях RouterOS 7.x парсер падає з
> `expected end of command` на підкресленні `_` в іменах змінних. Тому всі
> змінні конфігів — у lowerCamelCase: `routerHost`, `enableGuest`,
> `wifiPassword` тощо. Значення (імена address-list `bf_stage1` тощо) — не
> ідентифікатори, тому підкреслення у них дозволені.

Усі налаштування — на початку кожного `config.rsc` у блоці `:global`.
Скрипт `setup.sh` читає з цього ж блоку параметри підключення:

| Змінна | Призначення | Використовує |
|--------|-------------|--------------|
| `routerHost` | IP/домен роутера | setup.sh |
| `routerUser` | SSH-користувач | setup.sh |
| `routerPassword` | SSH-пароль (якщо без ключа) | setup.sh |
| `routerSshPort` | SSH-порт (за замовчуванням 22) | setup.sh |
| `configFile` | ім'я файлу на роутері | setup.sh |
| `adminUser`, `adminPassword` | адміністратор роутера | конфіг |
| `enableWireguard` | тумблер WireGuard VPN | конфіг |
| `enableBruteforce` | тумблер захисту від брутфорсу (SSH/Winbox з WAN) | конфіг |
| `enableBackup` | тумблер щоденного бекапу (скрипт + планувальник) | конфіг |
| `enableNightLed` | тумблер нічного режиму LED (`false` за замовчуванням) | конфіг |
| `bfPorts` | порти для захисту від брутфорсу (за замовчуванням `22,8291`) | конфіг |
| `bfStageTimeout` | таймаут стадій (`1m`) — вікно, за яке треба «наїздити» 3 спроби | конфіг |
| `bfBlacklistTime` | час блокування джерела в чорному списку (`10d`) | конфіг |
| `enableGuest` | тумблер гостьової мережі (VLAN 20) | конфіг |
| `enableIot` | тумблер IoT мережі (VLAN 30) | конфіг |
| `enableWifi2Ghz` | тумблер радіо 2.4 ГГц | конфіг |
| `enableWifi5Ghz` | тумблер радіо 5 ГГц | конфіг |
| `vlanLan/GUEST/IOT`, `NET_*`, `IP_*`, `GW_*`, `POOL_*` | мережа VLAN 10/20/30 | конфіг |
| `wifiSsid/PASSWORD`, `GUEST_*`, `IOT_*` | три SSID | конфіг |
| `wgPort`, `wgAddr`, `wgNet`, `wgPeerAddr`, `wgPeerKey` | WireGuard | конфіг |
| `TIMEZONE`, `ntpServer1/2`, `routerIdentity`, `backupStartTime` | система | конфіг |
| `nightLedInterval` | інтервал нічного LED (`23:00-07:00`) | конфіг |

> **Пароль адміністратора** зберігається у `config.rsc` (`adminPassword`) —
> не комітьте заповнений файл у Git і не публікуйте його.

### Автентифікація SSH

- **Ключ** (пріоритет): опція `--key <шлях>` або змінна `SSH_KEY`.
- **Пароль**: береться зі змінної `routerPassword` з `config.rsc`,
  потребує `sshpass` (`apt install sshpass`).

## Що налаштовує конфіг

1. Система: ім'я, час, NTP, логи
2. Користувачі: власний адмін, дефолтний `admin` вимкнено
3. Bridge з VLAN-фільтрацією: VLAN 10 (LAN), 20 (GUEST), 30 (IoT)
3а. Списки інтерфейсів: WAN, LAN (завжди), GUEST/IOT (за тумблерами)
4. WiFi: три SSID (основна / гостьова / IoT), WPA2-PSK (ac²/ac³ — WPA2+WPA3)
5. WAN: DHCP-клієнт провайдера
6. IP + DHCP-сервери на кожен VLAN
7. DNS: кешуючий, upstream `1.1.1.1,9.9.9.9`
8. Firewall: isolation GUEST/IOT ↔ LAN, NAT, захист служб, UPnP off,
   захист від брутфорсу SSH/Winbox (лише WAN), `tcp-syn-cookie`,
   анти-спуфінг RAW, PMTU ICMP, логування фінальних drop
9. WireGuard VPN (10.10.100.0/24)
10. Щоденний бекап о 03:00 (`.backup` + `.rsc`)

## Тумблери (ENABLE_*)

Усі тумблери — у блоці змінних кожного `config.rsc`. Значення `true`/`false`.

| Тумблер | Що вимикає (false) |
|---------|--------------------|
| `enableWireguard` | інтерфейс `wg-vpn`, адресу, пір, firewall-правило порту, членство в LAN |
| `enableGuest` | VLAN 20, DHCP, SSID гостьової, DNS/ізоляцію у firewall, список `GUEST` |
| `enableIot` | VLAN 30, DHCP, SSID IoT, DNS/ізоляцію у firewall, список `IOT` |
| `enableWifi2Ghz` | радіо 2.4 ГГц (`disabled=yes`), VAP-и на ньому, bridge-порт |
| `enableWifi5Ghz` | радіо 5 ГГц (`disabled=yes`), VAP-и на ньому, bridge-порт |
| `enableBackup` | скрипт `backup-daily` та планувальник бекапу |
| `enableNightLed` | правило нічного гасіння `user-led` (інтервал — `nightLedInterval`) |

### Захист від брутфорсу

За тумблером `enableBruteforce` (працює незалежно від інших тумблерів):

- захищаються порти зі змінної `bfPorts` (зв'язані з `/ip service`:
  ssh=22, winbox=8291 — якщо зміните порт служби, оновіть і `bfPorts`);
- діє **тільки на TCP-пакети до захищених портів з WAN**
  (`in-interface-list=WAN`) — клієнти LAN, у т.ч. по WiFi (wlan),
  ніколи не потрапляють у списки;
- каскад: 3 пакети за вікно `bfStageTimeout` → чорний список
  на `bfBlacklistTime`, далі — drop;
- правила каскаду не фільтруються за `connection-state`, тому правило
  drop з чорного списку, розташоване **перед** accept
  established/related, блокує джерело негайно — навіть поки живі
  його старі з'єднання (адміністрування з WAN не передбачене:
  доступ лише через LAN або WireGuard);
- перевірка на роутері: `/ip firewall address-list print` (списки
  `bf_stage1`, `bf_stage2`, `bf_blacklist` динамічні).

### Шари захисту firewall (розділ 8 конфігу)

Порядок input-ланцюжка: BF-drop → established/related → invalid →
служби → решта.

| Захист | Що робить |
|--------|-----------|
| BF-каскад (за тумблером) | чорний список брутфорсерів SSH/Winbox з WAN, діє перед established |
| `tcp-syn-cookie=yes` | SYN-cookie у connection tracking (пом'якшує SYN-шторм) |
| PMTU ICMP | accept type 3 (fragmentation needed) без ліміту — важливо для masquerade |
| Анти-спуфінг RAW | drop з WAN пакетів із приватними джерелами (RFC1918/loopback/CGNAT) |
| DHCP 67-68 | accept для GUEST/IOT — без цього гостьові/IoT-клієнти не отримують адрес |
| Служби `address=$netLan,$wgNet` | SSH та Winbox обмежені самим RouterOS (LAN + WireGuard), а не тільки firewall |
| Ізоляція VPN | GUEST/IOT не мають доступу до WireGuard-підмережі (10.10.100.0/24) |
| Логування drop | фінальні input/forward-drop пишуться в лог (`log-prefix="fw-*"`) |

> Раніше тут був «SYN-flood ліміт» (`drop ... limit=50,10:packet`) — правило
> з інвертованою логікою (drop матчав пакети *в межах* ліміту) і вилучено:
> фінальний `drop` з WAN та `tcp-syn-cookie` дають той самий результат.

Правила взаємодії:
- вимкнене радіо також вимикає гостьову/IoT VAP на ньому (навіть якщо
  `enableGuest`/`enableIot = true`);
- основний SSID і дротовий LAN працюють завжди;
- радіо вимикається як `disabled=yes` (оборотно), а не видаляється.

Типові сценарії:

| Сценарій | Тумблери |
|----------|----------|
| Повний функціонал | усі `true` |
| Тільки дротовий роутер | `enableWifi2Ghz=false`, `enableWifi5Ghz=false` |
| Без гостьової мережі | `enableGuest=false` |
| Без VPN | `enableWireguard=false` |
| Лишнь IoT (наприклад, для Wi-Fi-лампочки) | `enableGuest=false` |

## Вимоги

- RouterOS 7.14+ (для hAP ac²/ac³ — 7.16+, бо віртуальні AP через `parent=`)
- На робочій машині: `ssh`, `scp`; `sshpass` — якщо без SSH-ключа

## Тестове середовище (VirtualBox/CHR)

Профіль `vbox-test` — прогін конфіга на RouterOS CHR у віртуальній машині
VirtualBox **з топологією, ідентичною реальному роутеру** (пакет `wifi`,
як на ac²/ac³; WiFi-розділ у профілі повністю відсутній — див. обмеження нижче).

### Розкладка VM

| VBox NIC | Мережа | MikroTik порт | Роль |
|----------|--------|---------------|------|
| NIC 1 | NAT | `ether1` | WAN (інтернет) |
| NIC 2 | host-only `vboxnet0` | `ether2` | LAN / керування з хоста |
| NIC 3–5 | internal | `ether3`–`ether5` | LAN-порти |
| NIC 6–8 | — | `ether6`–`ether8` | вільні (у CHR 8 портів) |

Якщо VM налаштована інакше — ремап (VM має бути вимкнена):

```bash
VBoxManage controlvm mikrotik poweroff
VBoxManage modifyvm mikrotik --nic1 nat
VBoxManage modifyvm mikrotik --nic2 hostonly --hostonlyadapter2 vboxnet0
VBoxManage modifyvm mikrotik --nic3 intnet --intnet3 ether3
VBoxManage modifyvm mikrotik --nic4 intnet --intnet4 ether4
VBoxManage modifyvm mikrotik --nic5 intnet --intnet5 ether5
VBoxManage startvm mikrotik --type headless
```

### Потік першого деплою

1. Хост: `sudo ip addr add 192.168.88.2/24 dev vboxnet0`
   (свіжий CHR тримає дефолтні `192.168.88.1` на LAN-мосту)
2. У `routers/vbox-test/config.rsc` лишається `routerHost "192.168.88.1"`
3. `./setup.sh --name vbox-test --reset`
4. Після перезавантаження роутер = `192.168.10.1` (VLAN 10 через `ether2`):
   `sudo ip addr del 192.168.88.2/24 dev vboxnet0 && sudo ip addr add 192.168.10.2/24 dev vboxnet0`
5. Змінити `routerHost` у профілі на `"192.168.10.1"` для наступних деплоїв

### Інспектування VM з хоста

```bash
VBoxManage showvminfo mikrotik --machinereadable | grep -E "^nic[0-9]=|^VMState=|^memory="
ip neigh show dev vboxnet0        # дізнатися адресу свіжого CHR
```

### Обмеження тесту

- WiFi-радіо у CHR відсутнє, тому WiFi-розділ у профілі vbox-test
  **повністю вилучений**: RouterOS валідує шляхи команд та імена інтерфейсів
  **при парсингу** — навіть невиконувана гілка `:if` зі згадкою `wifi1`/`wifi2`
  ламає весь імпорт (`expected end of command`).
- Охорон наявності WiFi в конфігах **немає** (вилучені): радіо скрізь
  керується тільки тумблерами `enableWifi2Ghz` / `enableWifi5Ghz`
  (`disabled=yes`, не видалення). Тому основні конфіги придатні лише для
  пристроїв із WiFi-пакетом; для CHR — окремий профіль `vbox-test`.
- CHR Free-ліцензія обмежує швидкість інтерфейсів 1 Мбіт (для тестів достатньо).

## Відновлення

Якщо після reset роутер недосяжний: Winbox через MAC-адресу (кнопка «...»
у Winbox Neighbors), або Netinstall.

> ⚠️ **Напівзастосований конфіг можливий.** `/import` (у т.ч. через
> `run-after-reset`) виконує рядки послідовно: збій на одному рядку
> (невідомий параметр версії RouterOS, відсутній інтерфейс, «already exists»)
> залишає раніше застосовану частину конфіга, а решту — ні. Особливо
> небезпечно: користувач створюється на початку, мережа — наприкінці.
> Тому конфіг закінчується **маркером успіху** — банером входу
> `CONFIG OK — import finished`:
> - банер видно → конфіг застосувався ПОВНІСТЮ;
> - банера немає → імпорт обірвався: працюйте через MAC-Winbox,
>   зайдіть у `/log print` і повторіть `/import file-name=config.rsc`,
>   або робіть reset ще раз.

## Відомі обмеження

- Конфіги не перевірялися на живому роутері — спочатку `--dry-run`,
  потім тестовий прогін на некритичному пристрої.
- `dhcp-options=hostname,clientid` та нумерація портів перевірені
  для RouterOS 7.x; на новіших версіях звірте `manual.mikrotik.com`.
- OpenTofu/IaC-автоматизація відкладена (раніше узгоджена) — провайдер
  `ddelnano/mikrotik` не покриває WiFi-wave2, NAT та firewall-изоляцію.
- Ротація бекапів у `backup-daily` спирається на порядок `/file find`,
  який залежить від версії RouterOS — перевірте на живому роутері.
- **IPv6 не налаштований** (ні адрес, ні firewall v6). Якщо провайдер
  видасть IPv6 (RA/DHCPv6), трафік піде без фільтрації на v6 — за потреби
  увімкніть `/ipv6 firewall` із дефолтним drop або залишіть IPv6 вимкненим
  на WAN.
- Сусідня директорія `../mikrotik/` — легасі-архів (не застосовувати);
  канонічні конфіги — лише тут, у `routers/`.
