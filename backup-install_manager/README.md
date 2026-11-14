# Backup Install Manager v2.0.2

Персональний інсталятор Arch Linux + менеджер dotfiles + бекапи + архіви.

Усі команди виконуються з кореня проєкту — каталогу, де лежить `backup-install_manager.sh`.

## Швидкий старт

    ./backup-install_manager.sh                    # інтерактивне меню
    ./backup-install_manager.sh sources scan       # подивитись, що є у $HOME
    ./backup-install_manager.sh sources doctor     # перевірити існування
    ./backup-install_manager.sh sources validate   # перевірити схему
    ./backup-install_manager.sh dotfiles backup    # Enter = усі

## Що всередині

    packages    — пакети за config/packages.conf
    dotfiles    — sync HOME ↔ dotfiles за config/dotfiles.conf
    sources     — list / doctor / validate / scan / add / remove
    archive     — tar.gz знімки dotfiles
    recovery    — захисні копії перед кожною зміною
    maintenance — очищення старих backup/логів

## Команди

```bash
./backup-install_manager.sh --help                   # повна довідка
./backup-install_manager.sh --version                # версія (src/core/version.sh)
./backup-install_manager.sh doctor                   # діагностика середовища
./backup-install_manager.sh test                     # регресійні тести

# Пакети
./backup-install_manager.sh packages --list          # перелік без встановлення
./backup-install_manager.sh packages cli shell       # встановити модулі
./backup-install_manager.sh packages --all           # усі модулі реєстру
./backup-install_manager.sh packages --dry-run all   # сухий прогін
./backup-install_manager.sh packages --configs-only --delete --yes cli

# Dotfiles: HOME ↔ dotfiles
./backup-install_manager.sh dotfiles backup [ШЛЯХ...]          # Enter = усі
./backup-install_manager.sh dotfiles backup changed [ШЛЯХ...]  # лише змінені
./backup-install_manager.sh dotfiles restore [ШЛЯХ...]         # dotfiles → HOME
./backup-install_manager.sh dotfiles status|verify|diff [ШЛЯХ...]  # читання
./backup-install_manager.sh dotfiles plan backup|restore [ШЛЯХ...] # план без дій
./backup-install_manager.sh dotfiles groups                    # перелік груп
# Додайте --group ГРУПА до будь-якого режиму Dotfiles.

# Швидкі псевдоніми (без префікса dotfiles)
./backup-install_manager.sh status|verify|diff [ШЛЯХ...]
./backup-install_manager.sh plan backup|restore [ШЛЯХ...]

# Довільні джерела та реєстр
./backup-install_manager.sh backup-src SRC REPO_SUB             # разовий бекап
./backup-install_manager.sh restore-src REPO_SUB [TARGET]      # повернути назад
./backup-install_manager.sh sources list|doctor|validate|scan
./backup-install_manager.sh sources add NAME TYPE PATH GROUP   # TYPE: home|system|"" 
./backup-install_manager.sh sources remove NAME

# Архіви, recovery, обслуговування
./backup-install_manager.sh archive list|create|restore NAME
./backup-install_manager.sh recovery list|verify ID|plan ID|restore ID [ШЛЯХ...]|delete ID
./backup-install_manager.sh backups list GROUP | verify GROUP ID
./backup-install_manager.sh maintenance menu|disk|cleanup TYPE|rotate TYPE KEEP
./backup-install_manager.sh logs path|tail [N]
./backup-install_manager.sh update RELEASE.tar.gz [--sha256 HASH] [--dry-run]
./backup-install_manager.sh modules list|info ID|deps ID|reverse ID|stats|plan
./backup-install_manager.sh report summary|modules
./backup-install_manager.sh smart [--dry-run] [модулі...]
```

## Прапорці

| Прапорець | Значення |
|---|---|
| `--dry-run` | показати заплановане без застосування, де підтримується |
| `--yes`, `-y` | пропуск підтверджень |
| `--no-color` | без ANSI-кольорів |
| `--verbose`, `-v` | додаткова діагностика |
| `--delete` | видаляти зайве на цільовій стороні синхронізації |
| `--backup` | форсовано увімкнути захисні копії на цей запуск |
| `--configs-only` | тільки конфігурації у Packages |
| `--no-configs` | не застосовувати конфігурації у Packages |
| `--strict-configs` | сувора перевірка конфігурацій |
| `--all` | усі модулі Packages |

Прапорці можуть стояти до або після команди; не всі мають сенс для кожної команди.

## Бекапи та безпека

- Захисні копії перед кожною зміною **увімкнені за замовчуванням**
  (`SETUP_BACKUP_ENABLED=true`). Прапорець `--backup` форсовано вмикає їх,
  навіть якщо конфігурація вимкнула.
- Для змін спершу запускайте `--dry-run` або `dotfiles plan`.
- `--delete` видаляє зайві файли на цільовій стороні. Спершу перевіряйте
  перелік змін (`plan`, `status`). При вимкнених захисних копіях
  (`SETUP_BACKUP_ENABLED=false`) `--delete` працює, але без автоматичного
  відкату — у журналі з'явиться попередження.
- Відновлення знімків recovery з `--delete` вимагає `SETUP_RECOVERY_ENABLED=true`.
- System restore до `/etc` завжди створює власну захисну копію й не підтримує `--delete`.
- Команди змін використовують lock `.setup-manager.lock`; код 75 означає
  конфлікт блокування/очікування. Не запускайте з root без необхідності.

Послідовність відновлення:

```bash
./backup-install_manager.sh recovery list              # перелік захисних знімків
./backup-install_manager.sh recovery verify ID         # перевірка manifest і SHA-256
./backup-install_manager.sh recovery plan ID           # що буде відновлено (без дій)
./backup-install_manager.sh recovery restore ID        # реальне відновлення знімка
./backup-install_manager.sh backups list dotfiles      # резервні копії групи
./backup-install_manager.sh backups verify dotfiles ID # перевірка цілісності
```

`recovery verify` перевіряє manifest і контрольну суму, якщо вони наявні;
код 3 означає legacy-копію без сум (цілісність не підтверджена).
`recovery delete ID` незворотний. Відновлення не є гарантією атомарного
відкату всього набору файлів.

## Конфігурація

`config/setup.conf` (Bash-файл; не додавайте неперевірений код):

```bash
SETUP_KEEP_DAYS=30                      # скільки днів зберігати backup/логи
SETUP_ARCHIVE_PREFIX="dotfiles-backup"  # префікс імен архівних файлів
SETUP_BACKUP_ENABLED=true               # захисні копії перед змінами (за замовчуванням true)
SETUP_RECOVERY_ENABLED=true             # recovery-знімки файлових операцій
SETUP_LOCK_TIMEOUT=0                    # очікування блокування, с (0–300; 0 — не чекати)
```

`config/packages.conf` — INI-реєстр модулів, не виконуваний код. Порядок
секцій визначає порядок встановлення. Поля секцій: `title`, `pacman`, `aur`,
`configs`, `configs_group`, `hooks`, `hook.ПАКЕТ`, `config.ПАКЕТ`, `depends`
(останнє — лише для аналітики `modules plan`).

`config/dotfiles.conf` — реєстр джерел: ім'я, режим (`home`, `system` або
порожній для абсолютного шляху), шлях, група. Після редагування:

```bash
./backup-install_manager.sh sources validate   # перевірка схеми
./backup-install_manager.sh sources doctor     # чи існують шляхи
./backup-install_manager.sh dotfiles plan backup   # план без дій
```

Редагуйте користувацькі конфігурації тільки після резервної копії.
Не підміняйте `config/` або `dotfiles/` при розпакуванні нового релізу.

## Кольорові статуси та коди завершення

`dotfiles status`, `dotfiles diff` і `dotfiles verify` завершуються з кодом **0**,
навіть коли файли відрізняються або відсутні; код **2** означає помилку.
`[OK]` — зелений, `[NEW]` (тільки HOME) — блакитний, `[CHANGED]` — жовтий,
`[DEL]` (тільки dotfiles) — червоний. Для вкладених каталогів виводяться
відсутні файли. `[UNTRACKED]` означає, що файл у `dotfiles` не описаний
у `dotfiles.conf`: його HOME-шлях невідомий.

За замовчуванням кольори вмикаються лише в терміналі. `--no-color` або
`NO_COLOR=1` прибирає ANSI; `SETUP_COLOR=always` примусово вмикає їх
для сумісних терміналів.

## Структура проєкту

Увесь програмний код розташовано у `src/` за відповідальністю: `core/`, `cli/`, `packages/`, `dotfiles/`, `recovery/`, `hooks/`, `diagnostics/`.

- `backup-install_manager.sh` — єдина точка входу CLI.
- `hooks/` — тільки функції `hook_main()`, які викликає `src/hooks/hook_runtime.sh`.
- `config/` і `dotfiles/` — користувацькі налаштування та дані.
- `tools/` — інструменти міграції та перевірки захисних копій.
- `tests/` — незалежні Bash-тести.
- `logs/`, `backups/`, `archives/` — локальні runtime-дани, які не входять до релізного архіву.

Зміни структури потребують одночасного оновлення README та CHANGELOG нижче.

## Останні зміни

Актуальна версія коду: **2.0.2** (джерело — `src/core/version.sh`).

### 2026-11-14 — прапорці --delete та --backup

- `--sync-delete` перейменовано на `--delete` (старий прапорець видалено).
- Захисні копії увімкнені за замовчуванням; `--no-backup` видалено,
  замість нього додано `--backup` (форсоване вмикання на один запуск).
- `config/setup.conf`: `SETUP_BACKUP_ENABLED=true` за замовчуванням.
- Документацію `docs/` консолідовано в README.md.

### 2026-11-12 — --delete без захисних копій

- `--delete` не відхиляється при вимкнених захисних копіях: замість помилки —
  одне попередження «автоматичний відкат недоступний».
- Запобіжник залишено лише для recovery-restore (`SETUP_RECOVERY_ENABLED=true`
  обов'язкове) та system restore (завжди зі власною копією).

### 2026-10-22 — v2.0.2

- Аудит перейменування: точка входу `backup-install_manager.sh` в CLI,
  документації й тестах; валідація релізу в `tools/update_safe.py`;
  службовий `dotfiles/.keep` для комплектності релізу.
- Remote Sync (ПК ↔ сервер) не реалізовано й не документується як доступна команда.
