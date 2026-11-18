# MikroTik hAP AC — домашня конфігурація

Комплект конфігурації MikroTik RouterOS 7.20+ з ручним вибором Wi-Fi драйвера.

## Структура

```text
mikrotik-hap-ac-release/
├── README.md
├── setup.sh
├── routers/
│   ├── hap-ac/
│   │   └── config.rsc
│   └── vbox-test/
│       └── config.rsc
└── tests/
    ├── test-local.sh
    └── test-rsc-static.py
```

## Перед першим запуском

1. Відредагуйте `routers/hap-ac/config.rsc`.
2. Виберіть `wifiDriver`: `legacy`, `wifi-qcom-ac` або `wifi-qcom`. Сумісність драйвера з моделлю/архітектурою автоматично не перевіряється.
3. Для `wifi-qcom-ac` та `wifi-qcom` вручну задайте `wifi2GhzInterface` і `wifi5GhzInterface` відповідно до `default-name` фізичних радіо пристрою. Початкові значення — `wifi2` для 2.4 GHz та `wifi1` для 5 GHz; перевірте їх перед використанням.
4. Замініть `ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА`, `ЗАМІНІТЬ_ПАРОЛЬ_WIFI`, а також паролі Guest/IoT, якщо ці мережі ввімкнені.
5. Для WireGuard у режимах `ip` та `mikrotik-ddns` задайте публічний ключ клієнта `wgPeerKey`.
6. Якщо вибрано `wgEndpointMode "ip"`, задайте `wgEndpointIp`.
7. Доступ SSH/Winbox через WireGuard-тунель керують `enableWgSsh` та `enableWgWinbox` (за замовчуванням увімкнені; при `wgEndpointMode "disabled"` ігноруються).
8. Для WAN-адміністрування залишайте обидва перемикачі вимкненими, якщо воно не потрібне. Якщо вмикаєте — задайте `wanAdminAddresses` довіреними IP/CIDR.
9. Для парольної SSH-автентифікації задайте `routerPassword`. Альтернатива — SSH-ключ через `--key`.

## Wi-Fi

- `wifiDriver="legacy"` використовує `/interface wireless`.
- `wifiDriver="wifi-qcom-ac"` використовує `/interface wifi` з діапазонами 802.11n/ac.
- `wifiDriver="wifi-qcom"` використовує `/interface wifi` з діапазонами 802.11ax.
- Якщо `enableWifi2Ghz=false` та `enableWifi5Ghz=false`, весь блок Wi-Fi пропускається. Профілі безпеки, віртуальні AP і bridge-порти Wi-Fi не створюються; Wi-Fi паролі не є обов'язковими.
- Гостьова та IoT Wi-Fi мережі створюються лише коли ввімкнено 2.4 GHz.
- Для нових драйверів імена фізичних радіо задаються вручну через `wifi2GhzInterface` та `wifi5GhzInterface`.

Для hAP AC (RB962UiGS-5HacT2HnT) використовується `legacy`. Значення `wifi-qcom-ac` та `wifi-qcom` не призначені для цього MIPSBE-пристрою; конфігурація навмисно не визначає сумісність автоматично.

## WireGuard

`wgEndpointMode` має три варіанти:

- `ip` — endpoint клієнта `wgEndpointIp:wgPort`;
- `mikrotik-ddns` — endpoint клієнта з доменом, який показує `/ip cloud print`, і портом `wgPort`;
- `disabled` — WireGuard не створюється.

MikroTik Cloud DDNS лише оновлює DNS-ім'я. Він не обходить CGNAT. Якщо WAN IPv4 роутера приватна/CGNAT, вхідний WireGuard через IPv4 не запрацює без публічної адреси/портфорвардингу, глобального IPv6 або окремого зовнішнього вузла (наприклад VPS).

Цей hAP AC має MIPSBE, тому MikroTik Back To Home для нього не є доступним варіантом.

Адміністрування через тунель керують окремі перемикачі `enableWgSsh` та `enableWgWinbox`: коли WireGuard створюється (`wgEndpointMode` не `disabled`) і тумблер увімкнений, відповідна служба додатково приймає підключення з `wgNet` (Winbox → `10.10.100.1:routerWinboxPort`, SSH → `10.10.100.1:routerSshPort`). При `wgEndpointMode "disabled"` тумблери не мають ефекту.

## Профілі та їхні відмінності

`test-rsc-static.py` перевіряє всі профілі `routers/*/config.rsc`: баланс дужок, невизначені `$змінні`, невідомі плейсхолдери.

Профілі `hap-ac` та `vbox-test` свідомо різняться; ці відмінності не є помилками:

- **Wi-Fi** — лише в `hap-ac`; CHR у VirtualBox не має радіомодулів, блок Wi-Fi в `vbox-test` відсутній.
- **Bruteforce** — в `hap-ac` стадійні правила звужені до `connection-state=new` та `tcp-flags=syn,!ack`; в `vbox-test` збираються всі нові TCP-пакети на адмін-портах.
- **ICMP** — `hap-ac` дозволяє весь ICMP з WAN (діагностика, PMTU); `vbox-test` обмежує типами (PMTU та echo-reply з лімітом).
- **NAT** — `hap-ac` маскарадить лише мережі зі списку `NAT_ALLOWED`; `vbox-test` маскарадить усе з WAN (лабораторне середовище).
- **RAW-правила** — анти-спуфінг приватних джерел та захист DNS є лише в `vbox-test`.
- **Ідемпотентність** — `vbox-test` створює записи умовно, тому імпорт можна повторювати; `hap-ac` використовує безумовні `add` і розрахований на чисту конфігурацію після `--reset`.

## Порти адміністрування

`routerSshPort` — порт SSH-служби, який задає конфігурація, і порт, на якому підключається `setup.sh`. `routerWinboxPort` — порт служби Winbox (за замовчуванням `8291`). Якщо змінюєте будь-який з портів, додайте нове значення до `bfPorts`, інакше bruteforce-захист лишиться на старому порту.

## Запуск

Лише перевірити локальні параметри та показати план (без SSH/SCP):

```bash
./setup.sh --name hap-ac --dry-run
```

Завантажити файл, не застосовуючи його:

```bash
./setup.sh --name hap-ac --key ~/.ssh/id_ed25519
```

Або з парольним SSH (потрібен `sshpass`):

```bash
./setup.sh --name hap-ac
```

Деструктивний reset із подальшим автоматичним імпортом:

```bash
./setup.sh --name hap-ac --reset
```

На Arch Linux:

```bash
sudo pacman -S openssh sshpass
```

`--reset` видаляє поточну конфігурацію. Перед запуском перевірте резервний спосіб локального доступу (наприклад, MAC Winbox/консоль) та переконайтеся, що паролі й мережеві параметри правильні. Скрипт блокує реальну передачу, якщо в активних функціях залишилися плейсхолдери.

## Ручне застосування

Якщо файл лише завантажений, імпорт запускається вручну на MikroTik:

```routeros
/import file-name=config.rsc
```

Конфігурація розрахована на чисту систему після `--reset`. Повторний імпорт поверх уже налаштованого роутера не є повністю ідемпотентним.
