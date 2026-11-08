# CHANGELOG — MikroTik Manager Bash

Консолідований журнал усіх великих змін проєкту. Актуальний прогін тестів наведений окремо в кожному розділі на момент останньої зміни.

## Поточний стан (2026-11-06)

| Перевірка | Результат |
|---|---:|
| Локальний тестовий набір | **257 checks: 253 PASS / 0 FAIL / 4 SKIP** |
| Валідація профілів `home-router` та `chr` | PASS |
| Bash syntax / Python compile / JSON parse | PASS |
| ShellCheck (`-S warning`) | чистий (лише 1 відоме хибне спрацювання SC2088 у `expand_path` на шаблоні `"~/"`) |

Чотири SKIP — інтеграційні сценарії, що потребують фактичного RouterOS: SSH upload, backup/reset, імпорт SSH key та імпорт/виконання RSC. Реальний маршрутизатор не використовувався.

## Fix: false-FAILED імпорту SSH ключа (2026-11-08)

- Діагностика на RouterOS 7.24.6 (CHR, VirtualBox) підтвердила: після успішного `/user ssh-keys import` RouterOS **сам видаляє pub-файл** (`/file add` type=ssh key size 97 → імпорт → файл зник, ключ у `/user ssh-keys print` присутній).
- Через це фінальний сліпий `/file remove $mgrKeyFile` у блоці імпорту кидав «failure: file does not exist» → цілий блок on-error → `mgr: FAILED: users: import SSH key <user>#1` та `apply failed token=... errors=1` попри повний успіх (ключ імпортовано, логін по ключу працював).
- Побічний ефект робочий: `mgrErrors=1` → скрипт пропускає вимкнення admin (`skip disabling admin`).
- Фікс у `gen_users`: прибрано фінальний сліпий `/file remove` і прибрано `:delay 1s` (перевірка `find` за fingerprint синхронна — миттєвий find після імпорту повертає ключ). Видалення старого файлу перед `/file add` залишилось.
- Прибрано опитування журналу після reset (`wait_for_reset_apply` → no-op) та мертві налаштування `reset.wait_timeout_seconds`/`reset.poll_interval_seconds` зі схеми, валідації та README; раннє die про зміну SSH host key прибрано.
- Тест `SSH key is verified before temporary file cleanup` замінено на `SSH key is verified (no blind temporary file cleanup)`; тест `negative: create=true without password rejected` більше не залежить від живого стану профілю (sed вирізає password-рядки).
- Прогін: **261 checks: 257 PASS / 0 FAIL / 4 SKIP**.

## Home Use Cleanup (2026-11-05)

### CLI

- Скорочено CLI help з 226 до 57 рядків; всі операції збережено (`--list`, `--validate`, `--build`, `--upload`, `--backup`, `--secrets`, `--reset`, `--yes`, `--name`, `--output`, `--verbose`).
- Семантика операцій та порядок комбінацій не змінювалися.

### TOML та схема

- `[paths]`, `[backup]` і `[reset]` тепер необов'язкові; типові шляхи — `output/` та `backups/` усередині профілю.
- Типові параметри backup: `encrypt=false`, `remove_remote_after_download=true`.
- Типові параметри reset: `no_defaults=true`, `skip_backup=true`, `run_after_reset=true`, `require_confirmation=true`, timeout 300 секунд, poll 5 секунд. Reset усе одно запускається лише явним прапорцем `--reset`.
- `ntp.max_servers` необов'язковий (типовий ліміт — 4); у `[routerboard]` достатньо `supported`.
- Профілі чистилися від надлишкових значень, що збігаються з fallback: `home-router` 490→426 рядків, `chr` 333→275 рядків; згенеровані RouterOS-команди незмінні.

### Тести та секрети

- Тестовий runner створює синтетичні `.secrets` лише у тимчасових копіях; тести не залежать від приватних файлів і самодостатні.
- Приватні `.secrets` не потрапляють у ZIP/TAR.GZ релізи; `profiles/.secrets.example` залишено.

## Статична перевірка RouterOS (2026-11-05)

### Ізоляція Guest Wi-Fi

Раніше блокування guest → LAN покладалося лише на `firewall.forward_default_drop=true`. Тепер генератор додає **явні** правила до дозволу guest → WAN:

- `drop` із guest bridge до interface list `LAN`;
- якщо management list відрізняється від LAN — окремий `drop` до management list;
- після них — `accept` guest → WAN.

Додано регресійний тест із `forward_default_drop=false`, який перевіряє наявність правила ізоляції та його позицію перед дозволом WAN.

### DHCP pool і статичні leases

Валідація відхиляє:

- DHCP pool, що містить IP самого роутера, gateway, network або broadcast;
- статичну lease, що збігається з адресою роутера/gateway/network/broadcast;
- guest subnet, що перетинається з LAN або management-підмережею;
- guest DHCP pool, що містить адресу guest bridge.

### Brute-force port validation

`firewall.brute_force_ports` перевіряє межі 1..65535, правила запису одиночних портів та діапазонів, і що початок діапазону не більший за кінець.

### Порядок генерації (затверджений)

1. System, identity, clock, NTP, update channel.
2. Фізичні інтерфейси.
3. Bridge та його фізичні порти.
4. LAN і management IP addresses.
5. Interface lists.
6. Users і SSH keys.
7. IP services, discovery, MAC access.
8. Основні Wi-Fi інтерфейси.
9. Guest VAP та guest DHCP.
10. IPv4 firewall; 11. IPv6; 12. NAT і UPnP; 13. основний DHCP server/leases; 14. DNS; 15. WAN DHCP client — остання мережева операція; 16. apply result marker.

### Wi-Fi driver contracts

| Driver | RouterOS menu |
|---|---|
| `legacy` | `/interface wireless` — окремий bridge port |
| `wifi-qcom-ac` | `/interface wifi` — bridge через `datapath.bridge` |
| `wifi-qcom` | `/interface wifi` — bridge через `datapath.bridge` |

Guest VAP не отримує дубльований bridge port. Докладні правила: `WIFI-DRIVER-CONTRACTS.md`.

## Read-only Verification (2026-11-06)

- Команда `--verify` показує read-only RouterOS команди безпосередньо у stdout; створення `profiles/<profile>/output/<profile>-verify.rsc` прибрано, `--name`/`--output` для `--verify` відхиляються.
- Покриття: interfaces, bridge, DHCP, DNS, firewall, NAT, users, а також Wi-Fi для `legacy`, `wifi-qcom-ac`, `wifi-qcom`, `none` (меню обирається за `wireless.driver`).
- Усі команди — суто `print detail without-paging`; команд зміни конфігурації немає; SSH/SCP не запускаються; фактичний стан пристрою не читається (це лише попередній перегляд для ручного виконання оператором).

## Спрощення для домашнього використання (2026-11-06)

- Прибрано автостворення ключа цілісності та keyed HMAC секретів: заголовки `# config-sha256:`, `# secrets-sha256:`, `# apply-token:` у `.rsc` тепер суто інформаційні (bash-only, без python).
- Під час `--upload`/`--reset` застарілість RSC не блокується, окремий `.rsc` маркер "one-time reset" вилучено; повторний RESET тим самим файлом дозволений.
- Підтвердження RESET спрощено до `y/N` (або `--yes`); вимоги вводити назву профілю немає.
- Попередження про Wi-Fi паролі коротші за 12 символів показуються лише під час `--secrets` (під час введення), не при build.
- Прибрано спеціальні `reverse-proxy`-обробки в gen_firewall/gen_services/валідаторі: назви служб тепер мають належати стандартному набору IP-служб RouterOS (api, api-ssl, api-rest, ftp, ssh, telnet, winbox, www, www-ssl, grpc, grpc-ssl).
- Затвердження старих звітів об'єднано в цей файл; `ROUTEROS-STATIC-AUDIT.md`, `ROUTEROS-READ-ONLY-VERIFICATION.md`, `TEST-REPORT.md` вилучені.

## Профіль home-router: імпорт SSH-ключів (2026-11-08)

- Додано `ssh_keys = ["~/.ssh/id_mikrotik_lab.pub"]` для `users.admin` та `users.roman` у `profiles/home-router/config.toml` — раніше список був порожній, тому pub-ключ взагалі не імпортувався на роутер.
- Нюанс RouterOS задокументовано в README: після імпорту ключа парольний SSH-логін для цього користувача типово вимкнений (`/ip ssh set always-allow-password-login=yes` повертає, якщо потрібний).

## Фікс імпорту SSH pub-ключів (2026-11-08, за логом CHR 7.24.6)

- **Причина збою** (`mgr: FAILED: users: import SSH key roman#1` у логіроутера): RouterOS 7.24.6 відхиляє параметр `key-owner` у `/user ssh-keys import` — «bad parameter key-owner» (перевірено на роутері; стара сторінка документації його декларує, реальна побудова — ні). `on-error` перерізав увесь блок до `/file remove`, тому файл ключа залишався у root.
- Дедупе та після-імпортна верифікація переведені з ненадійного `key-owner` на **SSH fingerprint**: `/user ssh-keys find where user=... and fingerprint="SHA256:..."`. Fingerprint обчислюється локально як SHA-256 декодованого base64 тіла ключа (python3, нових залежностей немає; `=`-паддінг збігається з форматом RouterOS). Перевірено: без `=` RouterOS `find` не збігається (0 результатів), з `=` — збігається (1).
- Перевірено на CHR 7.24.6 по кроках: імпорт без `key-owner` працює; пошук `user`+`fingerprint` повертає імпортований ключ; повний згенерований блок імпорту виконано на роутері — дідупе пропускає вже імпортований ключ, службовий `.pub`-файл видаляється, помилок немає.
- У README оновлено опис: для повторних запусків ключ ідентифікується fingerprint, а не `key-owner`.

## Прибрано очікування після reset (2026-11-08)

- `wait_for_reset_apply` більше не опитує журнал RouterOS: менеджер відправляє `reset-configuration` і одразу завершує роботу з підказкою перевірити в журналі `mgr: apply done / apply failed token=<token>`.
- Раннє die при зміні SSH host key після reset прибрано; `ssh-keygen -R host` виконується вручну у зручний момент.
- Нажиткові налаштування `reset.wait_timeout_seconds` і `reset.poll_interval_seconds` вилучені зі схеми (lib/schema.json), валідації (toml_engine.py) та документів; у профілях не задані.

