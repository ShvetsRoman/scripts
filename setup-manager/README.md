# Setup Manager V1.3.0

Персональний інсталятор Arch Linux + менеджер dotfiles + бекапи + архіви.

## Швидкий старт

    ./setup.sh                    # інтерактивне меню
    ./setup.sh sources scan       # подивитись, що є у $HOME
    ./setup.sh sources doctor     # перевірити існування
    ./setup.sh sources validate   # перевірити схему
    ./setup.sh dotfiles backup    # Enter = усі

## Що всередині

  installer   — пакети за modules/*.sh
  dotfiles    — sync HOME ↔ dotfiles за config/sources.conf
  sources     — list / doctor / validate / scan / add / remove
  archive     — tar.gz знімки dotfiles
  recovery    — захист перед кожною зміною
  maintenance — очищення старих backup/логів

## Команди

    ./setup.sh installer --list
    ./setup.sh installer cli shell
    ./setup.sh installer --dry-run all

    ./setup.sh dotfiles backup [шлях...]
    ./setup.sh dotfiles backup changed [шлях...]
    ./setup.sh dotfiles restore [шлях...]
    ./setup.sh dotfiles status [шлях...]
    ./setup.sh dotfiles verify [шлях...]
    ./setup.sh dotfiles plan backup [шлях...]
    ./setup.sh dotfiles plan restore [шлях...]
    ./setup.sh dotfiles diff [шлях...]

    ./setup.sh backup-src SRC REPO_SUB
    ./setup.sh restore-src REPO_SUB [TARGET]

    ./setup.sh sources list|doctor|scan|add|remove

    ./setup.sh archive list|create|restore NAME
    ./setup.sh recovery list|verify ID|plan ID|restore ID [REL...]|delete ID
    ./setup.sh backups list GROUP
    ./setup.sh backups verify GROUP ID
    ./setup.sh logs path|tail [N]

    ./setup.sh maintenance menu|disk|cleanup TYPE|rotate TYPE KEEP
    ./setup.sh doctor
    ./setup.sh test

Повний перелік із прикладами — у docs/commands.md.

Зміни та обмеження v1.3.0 — у docs/CHANGELOG.md.

### Кольорові статуси та коди завершення

`dotfiles status`, `dotfiles diff` і `dotfiles verify` завершуються з кодом **0**,
навіть коли файли відрізняються або відсутні; код **2** означає помилку.
`[OK]` — зелений, `[NEW]` (тільки HOME) — блакитний, `[CHANGED]` — жовтий,
`[DEL]` (тільки dotfiles) — червоний. Для вкладених каталогів виводяться
відсутні файли. `[UNTRACKED]` означає, що файл у `dotfiles` не описаний
у `sources.conf`: його HOME-шлях невідомий.

За замовчуванням кольори вмикаються лише в терміналі. `--no-color` або
`NO_COLOR=1` прибирає ANSI; `SETUP_COLOR=always` примусово вмикає їх
для сумісних терміналів.

## Структура

    config/     setup.conf, sources.conf
    lib/        ядро (ui, path, fs, apply, sources, sync, ...)
    modules/    декларативні модулі пакетів
    tools/      archive_safe.py, update_safe.py, recovery_safe.py
    tests/      синтаксис + базові перевірки
    docs/       документація
    dotfiles/   репозиторій конфігів
    backups/    захист + recovery
    archives/   tar.gz знімки
    logs/       журнали

## Документація

  docs/commands.md — усі команди
  docs/sources.md  — формат реєстру
  docs/security.md — запобіжники


### Надійність v1.1.0

`./setup.sh sources validate` перевіряє схему, дублікати та перетин шляхів у `sources.conf`.
Команди запису мають ексклюзивний lock `.setup-manager.lock` (файл ігнорується Git).
`SETUP_LOCK_TIMEOUT` у `config/setup.conf` регулює очікування у секундах (0 — негайна помилка 75).
У `--dry-run` lock-файл не створюється. Перед оновленням перевірте `./setup.sh test` та `./setup.sh doctor`.

**Оновлення з 1.0.1:** `./setup.sh update` змінює код, але не змінює `config/setup.conf` та `config/sources.conf`.
З v1.1.0 фактична версія читається з `lib/version.sh`, щоб `--version` працював після code-only update.
Параметр `SETUP_LOCK_TIMEOUT` можна вручну додати до попереднього `setup.conf`; якщо параметра немає, діє значення `0`.

### Нове у v1.2.0

- `./setup.sh dotfiles plan backup|restore [NAME...]` — **тільки читання**: показує COPY/UPDATE/SKIP/MISSING/ERROR, а з `--sync-delete` також DELETE. Не виконує копіювання, не створює lock-файл.
- `./setup.sh dotfiles verify [NAME...]` — точна перевірка HOME ↔ dotfiles, зі статистикою. Повертає 0 при успішному порівнянні, навіть за наявності розбіжностей або відсутніх файлів; 2 — при помилці.
- `./setup.sh recovery verify ID` — перевірка SHA-256 вмісту знімка та `manifest.tsv`. Нові recovery-знімки містять `checksums.json`; невідповідність блокує restore. Старі знімки без контрольних сум мають код 3 (legacy); вони залишаються доступними для підтвердженого відновлення, але без гарантії перевіреної цілісності.
- `./setup.sh test` не очищає екран: змінна `SETUP_TEST_MODE` передається всім підтестам; для інших команд також доступно `SETUP_NO_CLEAR=true ./setup.sh ...`.
- Детальна статистика після backup, restore, plan, verify та recovery restore.

Операції plan/verify не гарантують, що між переглядом і реальним копіюванням файли не зміняться. Перевірка SHA-256 виявляє випадкове пошкодження, але не є цифровим підписом і не захищає від навмисної зміни даних та контрольних сум одночасно.

### Нове у v1.3.0 — Stability & Logging

- `dotfiles backup changed [NAME...]` порівнює вміст за `rsync -c`, створює/оновлює лише нові або змінені джерела з `sources.conf`. Незмінені об'єкти пропускаються. Без `--sync-delete` зайві файли в репозиторії залишаються.
- При **помилці копіювання або перевірки** виконується best-effort rollback **поточного** об'єкта з перевіреної SHA-256 копії. Це **не атомарна транзакція всього набору**, і не захищає від SIGKILL/втрати живлення. З `--no-backup` для вже існуючих цілей автоматичний rollback недоступний.
- Усі **нові захисні копії** містять `manifest.tsv` і `checksums.json`; `backups verify GROUP ID` перевіряє цілісність. Старі копії без manifest відображаються як legacy (код 3).
- `recovery plan ID [REL...]` показує майбутні операції без змін; `recovery restore ID [REL...]` дозволяє вибіркове відновлення за **точним** іменем з manifest (вміст усієї копії спочатку перевіряється).
- `maintenance rotate dotfiles 10` вручну залишає 10 найновіших копій, показує список видалень та запитує підтвердження; підтримує `--dry-run`. Ротація **не запускається автоматично**.
- Журнали містять дату/час, PID і ID запуску; `logs path` і `logs tail [N]` допомагають їх читати. Вміст логів може містити шляхи та назви конфігурацій, тому обмежуй доступ.
- Як і у v1.2.0, `./setup.sh test` не очищає екран.

### Статуси HOME ↔ dotfiles

Команда `./setup.sh dotfiles status` показує кольорові `[OK]`, `[CHANGED]`, `[NEW]`, `[DEL]` та `[UNTRACKED]` і підсумок. `[NEW]` означає об’єкт лише в HOME, `[DEL]` — лише в dotfiles, `[CHANGED]` — відмінність між двома сторонами, `[UNTRACKED]` — елемент у dotfiles без запису в `sources.conf`. Кількість `[NEW]`/`[DEL]` включає вкладені файли чи підкаталоги всередині `[CHANGED]`; відсутній підкаталог рахується одним елементом. Через це сума усіх міток може перевищувати число записів у реєстрі. Звичайні відмінності дають код 0; помилки перевірки — 2.
