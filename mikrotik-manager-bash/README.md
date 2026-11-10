# MikroTik Manager Bash

Менеджер профілів RouterOS 7. TOML-профіль проходить строгий розбір і перевірку схеми, після чого Bash-генератори створюють `.rsc`. Підтримуються локальна перевірка/генерація, окреме SSH/SCP завантаження готового RSC, backup/export, а також явний reset із `run-after-reset`.

> **Безпечний режим за замовчуванням:** `--build` і `--validate` не підключаються до маршрутизатора. `--upload` лише передає наявний RSC, нічого на ньому не застосовуючи. RESET, імпорт і застосування конфігурації в реальному RouterOS під час локальних тестів не виконувалися.

## Локальні команди

 Єдиний інструмент — `./mikrotik-manager.sh`; окремий інструмент збірки не потрібен.

```bash
./mikrotik-manager.sh --list                      # показати профілі та адреси роутерів
./mikrotik-manager.sh --validate --profile PROFILE
./mikrotik-manager.sh --build   --profile PROFILE
./mikrotik-manager.sh --help                      # повна довідка CLI
```

`--validate` і `--build` не підключаються до роутера. Локальний набір тестів
запускається напряму: `bash tests/run-tests.sh` (використовує mock-транспорти).

## Вимоги

- Bash 4.4+.
- Python 3.11+ (стандартний `tomllib`, без сторонніх Python-залежностей).
- OpenSSH `ssh` і `scp` потрібні для `--upload` та `--backup`.
- RouterOS 7 для цільового маршрутизатора.

Arch Linux зазвичай має Bash і Python у базовій системі. Перевірити:

```bash
bash --version
python3 --version
ssh -V
```

## Структура

```text
mikrotik-manager-bash/
├── mikrotik-manager.sh
├── lib/
│   ├── toml_engine.py
│   ├── routeros_verify.py
│   └── schema.json
├── profiles/
│   ├── .secrets.example       # шаблон; приватні .secrets не входять до релізу
│   ├── home-router/
│   │   ├── config.toml
│   │   ├── output/
│   │   └── backups/
│   └── chr/
│       ├── config.toml
│       ├── output/
│       └── backups/
└── tests/
    └── run-tests.sh
```

Журнали RouterOS (`log.txt` у корені) працювання в репозиторій не входять: вони містять приватну топологію (IP/MAC/fingerprint) і розміщуються лише локально.

Кожен профіль має власні `output/` і `backups/`. Типові шляхи не потребують TOML-секцій: `output/` для RSC та `backups/` для резервних копій. За потреби їх можна перевизначити в `[paths]`. Додаткові параметри SSH задаються в `[connection]`; шифрування backup — в `[backup]`; параметри руйнівної операції `--reset` — в `[reset]`. Ці секції необов'язкові: якщо їх немає, менеджер використовує безпечні типові значення. Інші розширені параметри firewall, NTP, оновлень і RouterBOARD можна додавати лише тоді, коли вони справді потрібні.

## Перший запуск або відновлення після reset

Перед `--upload` або `--backup` роутер має бути доступний по IP та SSH. Після команди
`/system reset-configuration no-defaults=yes skip-backup=yes` старі IP-адреси,
налаштування служб і firewall видаляються. Тому команди первинної підготовки
виконуються **локально в RouterOS** через консоль/serial або інший доступний
локальний спосіб керування — не через SSH.

### Фізичний MikroTik (реальний роутер)

1. Підключіть комп'ютер кабелем до LAN-порту роутера та відкрийте локальну
   консоль/термінал RouterOS. Після reset визначте інтерфейс, до якого підключений
   кабель, і перевірте, чи вже є IP-адреса:

   ```routeros
   /interface ethernet print
   /ip address print
   ```

2. Якщо адреси немає, виберіть вільну адресу роутера з тієї самої підмережі,
   що й адреса комп'ютера. **Не використовуйте `192.168.56.2` — це адреса лише
   лабораторної VirtualBox-схеми.** Наприклад, якщо ПК має `192.168.10.2/24`,
   а кабель підключений до `ether2`, виконайте:

   ```routeros
   /system identity set name=mikrotik
   /ip address add address=192.168.10.1/24 interface=ether2
   /ip service set ssh disabled=no
   /ip service set ssh available-from=192.168.10.2/32
   ```

   Тут `192.168.10.1/24` — приклад IP роутера, `ether2` — приклад LAN-порту,
   а `192.168.10.2/32` — IP комп'ютера, якому дозволено SSH. Замініть усі три
   значення відповідно до своєї мережі. Не припускайте, що `ether1` є LAN:
   на багатьох фізичних моделях він використовується як WAN.

3. Якщо це перший запуск із заводською конфігурацією і `/ip address print` уже
   показує адресу на bridge (наприклад, `192.168.88.1/24`), не додавайте другу
   адресу без потреби. Увімкніть SSH і обмежте доступ адресою свого ПК:

   ```routeros
   /system identity set name=mikrotik
   /ip service set ssh disabled=no
   /ip service set ssh address=192.168.88.2/32   # < 7.24; для 7.24+ — available-from=
   ```

   У прикладі `192.168.88.2` — адреса ПК; замініть її на фактичну. Якщо у вас
   інша заводська підмережа, використовуйте її адресу.

4. Оновіть `[connection]` у TOML-профілі: `host` — фактична IP-адреса роутера,
   `user` — наявний обліковий запис, `port` — SSH-порт (типово `22`). Переконайтеся,
   що пароль/SSH-ключ цього користувача дійсний.

### MikroTik CHR у VirtualBox

Це окрема схема для лабораторного профілю `chr`; вона не призначена
для фізичного роутера.

1. У налаштуваннях VM `mikrotik` перевірте, що Adapter 1 увімкнений і підключений
   до `Host-only Adapter` → `vboxnet0`, а Adapter 6 увімкнений у режимі `NAT`.
   Adapter 2–5 залиште підключеними до Internal Network для LAN-портів.
   На Arch Linux інтерфейс `vboxnet0` має адресу `192.168.56.1/24`.
2. Запустіть VM і через її консоль RouterOS (після reset — локально, до SSH)
   виконайте:

   ```routeros
   /system identity set name=mikrotik
   /ip address add address=192.168.56.2/24 interface=ether1
   /ip service set ssh disabled=no
   /ip service set ssh available-from=192.168.56.1/32
   ```

3. Переконайтеся, що `ether1` має прапорець `R` (running), IP керування
   призначено саме `ether1`, а `ether6` піднявся та отримав адресу через DHCP.
   На Arch Linux перевірте:

   ```bash
   ip -br address show vboxnet0
   ping -c 4 192.168.56.2
   nc -vz 192.168.56.2 22
   ssh admin@192.168.56.2
   ```

   Якщо `admin` не має пароля або RouterOS вимагає встановити його під час
   першого входу, завершіть цю процедуру в локальній консолі та використовуйте
   актуальні облікові дані. Не припускайте, що користувач `roman` існує після
   `no-defaults=yes`.

### Перед запуском менеджера

- Спочатку перевірте ручний SSH-вхід із комп'ютера.
- Переконайтеся, що `[connection].host`, `user`, `port` та `identity_file` у
  вибраному профілі відповідають фактичному доступу.
- Після reset SSH host key може змінитися. Перевірте fingerprint нового ключа
  окремо; лише після перевірки видаліть старий запис командою
  `ssh-keygen -R <IP_РОУТЕРА>`.
- Лише після цього запускайте `--validate --profile PROFILE`, `--build --profile PROFILE`,
  `--upload --profile PROFILE` або `--backup --profile PROFILE`. Для фізичного
  роутера спершу використовуйте `--upload` без `--reset`; повторне скидання для
  відновлення SSH не потрібне.

## Профілі

### `home-router`

Збережено переданий користувачем `config.toml`: LAN `192.168.88.1/24`, DHCP та 16 статичних leases, DNS, NAT, Firewall, служби, обидва Wi-Fi інтерфейси, користувачі та SSH connection. Оригінальне `generated_for = "RouterOS 7.23.8"` залишено без підміни.

Для генерації потрібні власні паролі. Створіть файл інтерактивно:

```bash
./mikrotik-manager.sh --secrets --profile home-router
```

Файл `profiles/home-router/.secrets` матиме права `600`. Приватні `.secrets`
не додаються до Git і не включаються до ZIP/TAR.GZ релізу; у пакет входить лише
`profiles/.secrets.example` без реальних значень.

### `chr`

Лабораторний профіль відтворює типову домашню схему RouterOS із фізичним
WAN, чотирма LAN-портами, NAT, DHCP, DNS та stateful firewall. Для збереження
керування CHR окремо використовується Host-only інтерфейс.

| RouterOS | VirtualBox Adapter | Призначення | Адреса/мережа |
|---|---:|---|---|
| `ether1` | 1 — Host-only `vboxnet0` | окреме керування | CHR `192.168.56.2/24`, host `192.168.56.1/24` |
| `ether2`–`ether5` | 2–5 — Internal Network | чотири LAN-порти в `bridge-lan` | `192.168.88.1/24` на bridge |
| `ether6` | 6 — NAT | WAN з DHCP від VirtualBox | адреса та default route автоматично |
| `MGMT` list | — | SSH/WinBox/ICMP із host-only | лише `192.168.56.0/24` |

**Параметри маршрутизатора:**

- LAN bridge `bridge-lan`, RSTP; `ether2`–`ether5` — його порти.
- LAN: `192.168.88.1/24`; DHCP pool `192.168.88.100–192.168.88.200`, lease 12 годин.
- DHCP-клієнти отримують шлюз `192.168.88.1` і DNS `192.168.88.1`.
- WAN: DHCP-клієнт на `ether6`, default route від DHCP; DNS провайдера не приймається.
- NAT: `srcnat masquerade` через interface-list `WAN`.
- DNS-кеш RouterOS доступний із LAN; upstream — Cloudflare Family `1.1.1.3`, `1.0.0.3`.
- Firewall: established/related accept, invalid drop, DHCP WAN/LAN, DNS із LAN,
  обмежений ICMP, LAN → WAN, дозволений dst-nat трафік і блокування нових
  неініційованих з’єднань із WAN; решта INPUT/FORWARD забороняється.
- SSH/WinBox доступні з management subnet `192.168.56.0/24`; Telnet, FTP,
  WWW та API вимкнені. MAC-доступ і Neighbor Discovery обмежені LAN.
- IPv6 вимкнено, оскільки цей лабораторний профіль налаштований на IPv4 NAT;
  окремий IPv6 WAN/Prefix Delegation тут не конфігурується.
- Статичні домашні DHCP leases і Wi-Fi не переносяться в CHR. `admin` лише
  вимикається (`create = false`, `enabled = false`). Користувач `roman`
  створюється з паролем з `.secrets` (ключ `USER_ROMAN_PASSWORD`) та активується;
  налаштований публічний ключ `~/.ssh/id_mikrotik_lab.pub` імпортується для нього.
- Параметри RouterBOARD пропускаються (`routerboard.supported = false`),
  оскільки CHR не має меню `/system routerboard`.

**VirtualBox:** залиште Adapter 1 у режимі Host-only `vboxnet0`, Adapter 2–5
підключіть до Internal Network (їх можна залишити окремими сегментами для
перевірки кожного bridge-порту), а Adapter 6 увімкніть у режимі NAT. Після
запуску CHR перевірте, що `ether6` має прапорець `R` і отримує DHCP lease.
Для тестування клієнта підключіть його мережевий адаптер до однієї з Internal
Network, призначених портам `ether2`–`ether5`; клієнт має отримати адресу з
`192.168.88.100–192.168.88.200` та виходити в Інтернет через NAT.

## Користувачі RouterOS та SSH-ключі

Кожен користувач описується окремою секцією `[users.<username>]`. `create` визначає,
чи створювати відсутній обліковий запис; `enabled` — чи має він бути активним
на роутері. `group` задає групу RouterOS. `password_file` і `password_key`
задаються парою. Для `create = true` пароль обов’язковий незалежно від
`enabled`: менеджер створить обліковий запис і встановить його кінцевий стан
(активний або вимкнений). Для `create = false` та `enabled = false` менеджер
не читає секрет і не змінює пароль — лише вимикає вже наявний обліковий запис.
Для `create = false` та `enabled = true` пароль змінюється лише якщо задано
`password_file`/`password_key`; без них наявний пароль не змінюється.
`ssh_keys` — список локальних шляхів до публічних ключів, які імпортуються
саме для цього користувача. Для повторних запусків ключ ідентифікується його
SSH fingerprint (`SHA256:...` — SHA-256 декодованого тіла ключа; збігається
з полем `fingerprint` у RouterOS `/user ssh-keys print`); вже імпортований
ключ пропускається. Зміна ключа додає новий, але старий не видаляється
автоматично.
`identity_file` у `[connection]` — приватний ключ
SSH-клієнта на комп’ютері й не імпортується на роутер автоматично.

Нюанс RouterOS: якщо для користувача імпортовано SSH-ключ, вхід для нього
**за паролем** через SSH типово вимкнений — увійти можна лише цим ключем.
Тому переконайтеся, що ключ працює (логініться ним до reset/після нього),
перш ніж розраховувати на нього без пароля. За потреби парольний логін
для користувачів із ключем можна повернути вручну:
`/ip ssh set always-allow-password-login=yes`.

Приклад: у профілі може бути будь-яка кількість користувачів, кожен зі своїм
списком ключів. `create = false` + відсутній користувач дає попередження,
а не створення. `enabled = false` вимикає наявний обліковий запис і пропускає
імпорт його ключів. Менеджер не видаляє користувачів або сторонні SSH-ключі.

```toml
[users.roman]
name = "roman"
enabled = true
create = false
group = "full"
password_file = ".secrets"
password_key = "USER_ROMAN_PASSWORD"
ssh_keys = ["~/.ssh/id_mikrotik_lab.pub"]
```

`[routerboard].supported` визначає, чи має цільовий пристрій RouterBOARD menu.
Для фізичного MikroTik встановлюйте `true`; для CHR у VirtualBox — `false`.
При `false` налаштування `/system routerboard settings` пропускається без
помилки та без збільшення `mgrErrors`.

## Wi-Fi drivers та контракти

`wireless.driver` приймає лише три драйвери (або `none` для профілів без Wi-Fi):

| Driver | RouterOS menu | Band contract | Channel width contract |
|---|---|---|---|
| `legacy` | `/interface wireless` | Legacy band values: `2ghz-b/g/n`, `2ghz-onlyn`, `5ghz-a/n/ac` тощо | Legacy values із суфіксами extension-channel, наприклад `20/40mhz-XX`, `20/40/80mhz-XXXX` |
| `wifi-qcom-ac` | `/interface wifi` | Wi-Fi 5/802.11ac: `2ghz-g`, `2ghz-n`, `5ghz-a`, `5ghz-an`, `5ghz-ac` | Новий формат: `20mhz`, `20/40mhz`, `20/40/80mhz`; 160 MHz та AX/6 GHz не допускаються |
| `wifi-qcom` | `/interface wifi` | Wi-Fi 6/AX: `2ghz-ax`, `5ghz-ax`, також сумісні режими `g/n/ac` і `6ghz-ax` | Новий формат `20mhz`, `20/40mhz`, `20/40/80mhz`, `20/40/80/160mhz` |

Для `wifi-qcom-ac` та `wifi-qcom` `band` і `channel_width` передаються в RouterOS без автоматичного обрізання або перетворення. `frequency = "auto"` означає, що параметр `channel.frequency` не генерується; для нового Wi-Fi stack також можна задати список частот/діапазонів у MHz. Сумісність діапазону/ширини перевіряється TOML engine до побудови RSC. Фактичні можливості конкретного радіомодуля залежать від моделі; їх потрібно звірити з `/interface wifi radio print detail` на відповідному пристрої.

Security contract: генератор підтримує PSK-автентифікацію. Для `legacy` дозволено `wpa-psk` та `wpa2-psk`; для обох нових драйверів — `wpa2-psk` та `wpa3-psk`. Enterprise/EAP та OWE не приймаються, оскільки поточна модель секретів задає PSK-пароль.

Для нового Wi-Fi stack `datapath.bridge` сам додає інтерфейс до мосту. Тому генератор не створює додатковий `/interface bridge port add` для master або guest VAP. Для `legacy` bridge port створюється окремою командою.

Докладні правила та тестові приклади: `WIFI-DRIVER-CONTRACTS.md`.

## Гостьовий Wi-Fi (`[wireless.guest]`)

Гостьова мережа — окремий SSID (Virtual AP) на тих самих радіо, з власним
містом, DHCP-пулом, DNS та ізоляцією від LAN. Клієнти гостей отримують вихід
лише в WAN (`masquerade` охоплює їх автоматично через `out-interface-list=WAN`),
тоді як доступ до LAN відсікається правилом `forward default drop` — гостьовий
міст не входить до списку `LAN`. Секція є опціональною: без неї гостьової
мережі не створюється.

```toml
[bridge.guest]                       # опційний окремий міст; якщо секції немає,
name = "bridge-guest"

[security.guest]                     # окремий профіль захисту та секрет
name = "guest-wifi-security"
authentication = "wpa2-psk"
password_file = ".secrets"
password_key = "GUEST_WIFI_PASSWORD"

[wireless.guest]
enabled = true
masters = ["@interfaces.wlan1", "@interfaces.wlan2"]  # радіо, на яких береться SSID (масив посилань interfaces.*)
name_prefix = "guest"                  # VAP-назви: guest-va1, guest-va2
ssid = "HOME-Guest"
security = "@security.guest"
bridge = "@bridge.guest"
address = "192.168.89.1/24"            # адреса роутера (і шлюз) у гостьовій мережі
pool_start = "192.168.89.100"
pool_end = "192.168.89.200"
dns_servers = ["192.168.89.1"]         # DNS для гостей (можна зовнішній)
lease_time = "12h"
```

Вимоги та перевірки: `wireless.enabled = true` з `driver != none`; кожен
`master` — активне Wi-Fi радіо (увімкнено в `[wireless.<radio>]` і
`[interfaces.<wlanN>]`); пул має належати `address`-підмережі; якщо
`dns_servers` містить адресу самого роутера — потрібно
`dns.allow_remote_requests = true`. `--secrets` автоматично запитує
`GUEST_WIFI_PASSWORD` разом з іншими секретами. Пароль гостей має бути
іншим, ніж пароль основного Wi-Fi.

Політика firewall для гостей: DHCP (udp 67→68) та ICMP на роутер, DNS 53
(лише якщо DNS-сервер — сам роутер і `allow_remote_requests=true`),
`chain=forward in-interface=<bridge-guest> out-interface-list=WAN accept`;
усього іншого — заборона. Гостьовий міст не додається до списку `LAN`,
тому `discovery` та MAC-доступ залишаються тільки для домашньої мережі.

## UPnP (`[upnp]`)

UPnP за замовчуванням вимкнено — генератор детерміновано виконує
`/ip upnp set enabled=no`. Увімкніть, коли потрібен автопроброс портів
(ігрові консолі, torrent-клієнти):

```toml
[upnp]
enabled = true
external = "@interfaces.ether1"        # зовнішній інтерфейс (interfaces.* або bridge.*)
internal = "@bridge.lan"    # внутрішній (LAN-міст або інтерфейс)
```

`external` і `internal` мають бути різними. UPnP дозволяє пристроям самим
відкривати порти на роутері — вмикайте свідомо, розуміючи, що будь-який
заражений пристрій у LAN може відкрити собі порт ззовні. Якщо UPnP
непотрібний — не додавайте секцію або тримайте `enabled = false`.

## Команди та CLI

CLI використовує прапорцевий синтаксис. Назва профілю завжди передається через
`--profile`; позиційні назви команд і профілів більше не використовуються.
Операції можна комбінувати, порядок прапорців у команді не має значення.
Назва профілю має починатися з латинської літери або цифри; далі дозволені
лише латинські літери, цифри, крапка, `_` та `-`. Пробіли, українські літери
і роздільники шляхів заборонені. Для `--output` права вже наявного
каталогу не змінюються; режим `700` встановлюється лише для щойно створеного.

```bash
# Довідка та список профілів
./mikrotik-manager.sh --help
./mikrotik-manager.sh --list

# Перевірка конфігурації без SSH
./mikrotik-manager.sh --validate --profile PROFILE

# Лише генерація RSC
./mikrotik-manager.sh --build --profile PROFILE
./mikrotik-manager.sh --build --profile PROFILE --name lab-check.rsc

# Показати read-only команди RouterOS у терміналі (без файлів і SSH)
./mikrotik-manager.sh --verify --profile PROFILE

# Лише завантаження вже згенерованого файлу (без повторної генерації)
./mikrotik-manager.sh --upload --profile PROFILE
./mikrotik-manager.sh --upload --profile PROFILE --name lab-check.rsc

# Явний каталог локальних RSC: build створює його, upload шукає файл у ньому
./mikrotik-manager.sh --build --profile PROFILE --output ./dist
./mikrotik-manager.sh --upload --profile PROFILE --output ./dist

# Права --output: існуючий каталог не змінюється; новий створюється з mode 700

# Генерація та завантаження: build завжди виконується першим
./mikrotik-manager.sh --build --upload --profile PROFILE --name lab-check.rsc

# Окремий backup/export або backup перед upload
./mikrotik-manager.sh --backup --profile PROFILE
./mikrotik-manager.sh --backup --upload --profile PROFILE

# Інші операції
./mikrotik-manager.sh --secrets --profile PROFILE
./mikrotik-manager.sh --verbose --build --profile PROFILE
```

### Семантика параметрів

- `--profile PROFILE` — обов'язковий для `--validate`, `--build`, `--verify`,
  `--upload`, `--backup` та `--secrets`.
- `--verify` — показує в терміналі read-only команди для перегляду стану RouterOS. Покриття: interfaces, bridge, DHCP, DNS, firewall, NAT, users і Wi-Fi відповідно до `wireless.driver`. Команда не створює `.rsc` або інших файлів, не підключається до роутера та не виконує команди. Для фактичної перевірки показані команди потрібно свідомо виконати в RouterOS.
- `--build` — генерує RSC локально з TOML. За замовчуванням файл зберігається
  у `profiles/<profile>/output/<profile>.rsc`.
- `--upload` — **тільки завантажує наявний локальний RSC**. Якщо файл відсутній
  або порожній, команда завершується помилкою з підказкою запустити `--build`.
  Локальний файл не генерується і не перезаписується.
- `--build --upload` — спочатку атомарно генерує RSC, потім завантажує саме цей файл.
- `--name FILE.rsc` — задає ім'я локального RSC для `--build` або `--upload`. Не підтримується для `--verify`, оскільки ця команда не створює файлів.
- `--output DIR` — перевизначає локальний каталог для RSC у `--build` або `--upload`. Не підтримується для `--verify`. Якщо не заданий,
  використовується `[paths].output_dir`, або `output/`, якщо `[paths]` відсутня.
  Для `--upload` файл шукається
  саме в обраному каталозі; upload не створює каталог і не генерує файл.
- `--backup` — створює RouterOS binary backup та export і зберігає їх у
  `profiles/<profile>/backups/` (або `[paths].backup_dir`). Самостійно не виконує reset. У комбінації з
  `--upload` backup виконується до передачі RSC.
- `--reset` — небезпечна дія, доступна лише разом із `--upload`; після передачі
  RSC виконується reset із `run-after-reset`. Потрібне підтвердження y/N
  (можна автоматично пропустити через `--yes`/`-y`). Менеджер не чекає
  перезавантаження: результат перевіряйте в журналі роутера —
  `mgr: apply done` / `mgr: apply failed token=<token>`.
- `--verbose` — показує додаткові шляхи локального й віддаленого RSC.

`--upload` без `--reset` не виконує `/import`, не застосовує конфігурацію і не
перезавантажує маршрутизатор. Після звичайного upload застосування виконується
вручну командою, яку менеджер виведе у повідомленні.

Reset руйнівний. Приклад із резервною копією та явним підтвердженням:

```bash
./mikrotik-manager.sh --backup --upload --reset --profile PROFILE
```

Для автоматизованого запуску підтвердження можна пропустити через `--yes`, але
використовуйте це лише після перевірки профілю та наявності резервної копії.
За замовчуванням backup RouterOS створюється без шифрування. Лише при
`backup.encrypt = true` обов’язково задаються `backup.password_file` і
`backup.password_key` (наприклад, ключ `BACKUP_PASSWORD` у `.secrets`). При
`encrypt = false` ці параметри не потрібні й команда `--secrets` їх пропускає.
Локальні файли backup мають права `600`; новостворений каталог backup — `700`.
Існуючі каталоги не отримують примусової зміни прав.

Необов'язкові секції конфігурації:

```toml
[paths]
output_dir = "output"
backup_dir = "backups"
remote_dir = ""
keep_rsc_on_router = false

[backup]
encrypt = false
remove_remote_after_download = true

[reset]
no_defaults = true
skip_backup = true
run_after_reset = true
require_confirmation = true
```

Залишайте ці блоки відсутніми, якщо типові значення підходять. Для шифрованого
backup додайте `password_file` і `password_key` у `[backup]`.

## RouterOS Read-only Verification

Команда `--verify` виводить у термінал перелік read-only команд для ручного перегляду стану RouterOS:

```bash
./mikrotik-manager.sh --verify --profile home-router
./mikrotik-manager.sh --verify --profile chr
```

Команда **не створює окремих `.rsc` файлів**, не змінює `profiles/*/output`, не виконує SSH/SCP і не підключається до роутера. Параметри `--name` та `--output` для `--verify` заборонені; вони залишаються доступними для `--build` і `--upload`.

Перелік охоплює інтерфейси й interface lists, bridge ports/VLAN, DHCP server/network/pool/leases, DNS settings/static records, firewall filter/raw/mangle/address lists, NAT, RouterOS users/groups/SSH keys та Wi-Fi. Для Wi-Fi враховується `wireless.driver`: `legacy` використовує `/interface wireless`, `wifi-qcom-ac` і `wifi-qcom` — `/interface wifi`; для `none` виводиться `SKIP`.

Усі RouterOS-команди мають суфікс `print detail without-paging`; `:put` використовується лише для заголовків. Це лише попередній перегляд команд: фактичний стан RouterOS не читається, доки оператор самостійно не виконає їх у RouterOS.

```bash
./tests/run-tests.sh
```

Тестовий набір створює тимчасову копію проєкту та використовує лише синтетичні тестові паролі. SSH/SCP і backup перевіряються mock-скриптами; окремий mock відтворює код 255 після RESET та успішне підтвердження apply-token. Реальне підключення до CHR, реальний backup/reset, імпорт SSH-ключа та виконання `.rsc` у RouterOS навмисно не запускаються.





## RouterOS Static Compatibility Audit

Після Home Use Cleanup проведено статичну перевірку генераторів RouterOS 7, firewall, DHCP, NAT, users та трьох Wi-Fi driver contracts. Виправлено ізоляцію Guest Wi-Fi від LAN, перевірки конфліктів DHCP pool/leases та валідацію портів brute-force захисту. Детальні звіти попередніх ітерацій (`ROUTEROS-STATIC-AUDIT.md`, `ROUTEROS-READ-ONLY-VERIFICATION.md`, `TEST-REPORT.md`) вилучені; актуальний стан — README, CHANGELOG і регресійний тестовий набір. Останній прогін тестів: **273 PASS / 0 FAIL / 4 SKIP** (SKIP — навмисні реальні SSH/reset-операції).



## Безпечне застосування користувачів та SSH-ключів

Активні користувачі створюються/оновлюються до відкладеного вимкнення старих облікових записів. SSH public key імпортується з верифікацією за SSH fingerprint (`/user ssh-keys find where user=... and fingerprint="SHA256:..."`); параметра `key-owner` у RouterOS 7.24 немає, тому він не використовується. Кожен крок імпорту (add file → import → verify) генерується як окрема команда `:do {...} on-error` з власною міткою `sshkey: ...` — журнало роутера локалізує крок відмови. Службовий `.pub`-файл RouterOS видаляє сам після успішного імпорту; при помилці файл залишається для діагностики. Якщо попередні кроки мають помилки (`mgrErrors > 0`), вимкнення старих облікових записів пропускається.

Перед `--reset` виконується read-only preflight SSH-запит: якщо канал недоступний, reset не відправляється. Код 255 після reset трактується як очікуваний розрив на перезавантаженні лише після успішного preflight.
