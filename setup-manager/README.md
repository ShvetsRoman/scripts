# Setup Manager V1.0.0 — перший стабільний реліз

**Увесь виконуваний код написано заново.** Із V3 перенесено лише списки пакетів 12 модулів (`modules/*.sh`) та реєстри конфігурацій (Installer `CONFIG_ITEMS` у `modules/*.sh` і Backup `config/dotfiles.conf`). Старі `install.sh`, `dotfiles-manager.sh`, їхні бібліотеки та тести не копіювалися.

## Запуск

```bash
./setup.sh --version
./setup.sh
./setup.sh doctor
./setup.sh packages --list
./setup.sh packages --dry-run cli
./setup.sh packages cli
./setup.sh dotfiles status
./setup.sh dotfiles backup
./setup.sh dotfiles restore .zshrc
./setup.sh dotfiles archive create
./setup.sh test
```

## Номер версії

Змінюється **тільки** у `config/setup.conf`: `SETUP_VERSION="1.0.0"`. Команда `./setup.sh --version` та заголовки використовують це значення.

## Незалежні реєстри

- `modules/*.sh`: списки Pacman, AUR, зовнішніх програм та installer-конфігів. Один файл = один модуль.
- `config/dotfiles.conf`: список шляхів для HOME → `dotfiles/` і відновлення назад.

## Важливі рішення щодо безпеки

- `--dry-run` не встановлює пакети та не змінює конфігурації.
- Відновлення створює захисну копію HOME, якщо `SETUP_RECOVERY_ENABLED=true`.
- `--no-backup` не відключає recovery відновлення.
- Сторонні install-скрипти за URL не виконуються автоматично; показується попередження.
- Перевірка наявності пакетів працює через поточні локальні бази Pacman/AUR. Мережевий збій може виглядати як відсутність пакета, тому перевіряйте `[WARN]`.
- В архіві V3 не було фактичного вмісту сховища dotfiles — перенесено лише реєстр шляхів. Перед `restore` потрібно зробити `backup` або самостійно покласти перевірені конфігурації у `dotfiles/`.
- `dotfiles/` може містити приватні дані. Перед git add перевіряйте його вміст.
- Значення `0` у вкладеному меню — назад, `00` — повний вихід.

## Перевірка перед встановленням

```bash
./setup.sh doctor
./setup.sh test
./setup.sh packages --configs-only --dry-run cli
./setup.sh packages --dry-run cli
```

Для роботи на Arch Linux потрібні `rsync`, `pacman`, `sudo`, а для AUR — `paru`. Не запускайте реальне встановлення пакетів до перевірки списків у `modules/*.sh`.

## Оновлення перевірок V1.0.0

- Для декларативних модулів використовуються точкові пояснення ShellCheck для динамічного `source`.
- Прибрано зайве поле `unused` з розбору реєстру конфігів; тип GitHub-елемента перевіряється перед обробкою.
- Додано `tests/test-configs.sh`: відсутній конфіг, однаковий вміст, зміна та `--dry-run`.
- Повторний `[INFO] ... вже синхронізовано` означає, що файл тепер **існує** в `dotfiles/` і збігається з HOME. Якщо джерело відсутнє, виводиться `[WARN] ... не знайдено`.
- Для діагностики ShellCheck на Arch Linux: `find . -type f -name '*.sh' -print0 | xargs -0 -r shellcheck -x --source-path=SCRIPTDIR -S style`.

## Розширення V1.0.0 — нові бібліотеки

- `lib/archive.sh`: створення, список та відновлення архівів сховища `dotfiles/`. Перед відновленням створюється захисний архів.
- `lib/recovery.sh`: перелік, відновлення та видалення захисних копій HOME з `backups/recovery/`.
- `lib/hooks.sh`: Docker user-group та Zsh як оболонка поточного користувача після встановлення модуля. Root-shell автоматично не змінюється.
- `lib/maintenance.sh`: перегляд розмірів і очищення logs/installer/dotfiles/recovery після `SETUP_KEEP_DAYS` повних діб; dry-run без підтвердження.
- `lib/git.sh`: init/status/log/diff/commit для Git у корені; `commit` використовує лише уже staged файли.

```bash
./setup.sh archive create
./setup.sh archive list
./setup.sh archive restore dotfiles-backup_YYYY-MM-DD_HH-MM-SS_PID.tar.gz
./setup.sh recovery list
./setup.sh recovery restore ID
./setup.sh recovery delete ID
./setup.sh maintenance disk
./setup.sh maintenance cleanup logs
./setup.sh git status
./setup.sh git log
./setup.sh git commit 'Оновити конфігурації'
```

Для неінтерактивних інтеграційних тестів підтвердження можна передати через `SETUP_ASSUME_YES=true`; використовуйте лише з довіреними даними.

## Installer: безпечне копіювання та повна синхронізація

- `./setup.sh packages --configs-only cli` — додає/оновлює файли за вмістом; зайві у HOME не видаляються.
- `./setup.sh packages --configs-only --sync-delete --dry-run cli` — показує заплановану повну синхронізацію без змін.
- `./setup.sh packages --configs-only --sync-delete cli` — видаляє зайве після резервної копії та інтерактивного підтвердження.
- `./setup.sh packages --configs-only --sync-delete --yes cli` — підтвердження без запиту (використовувати обережно).
- `--sync-delete --no-backup` заборонено. Без `--sync-delete` додаткові файли в HOME дозволені.

### Maintenance: безпечне очищення

```bash
./setup.sh maintenance disk
./setup.sh maintenance --dry-run cleanup dotfiles
./setup.sh maintenance cleanup dotfiles
./setup.sh maintenance cleanup logs
./setup.sh maintenance cleanup installer
./setup.sh maintenance cleanup recovery
```

Очищуються лише журнали `.log` або безпосередні каталоги відповідної категорії. Нові дані залишаються; за відсутності `--dry-run` потрібне підтвердження. Термін береться з `SETUP_KEEP_DAYS` у `config/setup.conf`. Якщо сам каталог або один із його батьків — символічне посилання, очищення відхиляється. Не запускайте очищення одночасно зі створенням backup.

## Єдине меню

Усі інтерактивні меню (головне, Installer, Dotfiles, Archive, Recovery та Maintenance) використовують однакові три колонки: номер, команда та опис. `0` повертає до попереднього меню; `00` завершує програму. На верхньому рівні обидва варіанти завершують роботу.

## Безпечне оновлення коду (V1.0.0)

Не розпаковуй новий повний архів поверх робочого каталогу — так можна повернути старі dotfiles. Використовуй команду:

```bash
./setup.sh update /шлях/до/setup-manager-v1.0.0-code-update.tar.gz --dry-run
./setup.sh update /шлях/до/setup-manager-v1.0.0-code-update.tar.gz
./setup.sh test
```

Оновлюються виключно `setup.sh`, `lib/`, `modules/`, `tests/`, `tools/`, `docs/`, `README.md`. Не оновлюються `dotfiles/`, `backups/`, `archives/`, `logs/` і весь `config/` (зокрема `config/setup.conf` та реєстр шляхів). Попередній код зберігається в `backups/updates/`; архів перевіряється до встановлення. Для безпечного оновлення та відновлення архівів потрібен `python3`.

**Важливо:** цей updater призначений для довірених релізних архівів. Він не перевіряє криптографічний підпис та не захищає від одночасного редагування файлів іншим процесом. Під час оновлення не запускай паралельно інші команди Setup Manager.

Archive Restore перевіряє структуру TAR, відкидає абсолютні та батьківські шляхи, символьні посилання, дублікати, нестандартні типи, надмірну кількість записів та завеликий розпакований обсяг; розпаковує лише у тимчасовий каталог перед заміною `dotfiles/`.

## Розміщення Git і фіксація V1.0.0

Батьківський `.gitignore` розташовано **поза** `setup-manager/`, у корені спільного Git-репозиторію. Setup Manager не створює і не змінює цей файл під час code-only update. Якщо у батьківському Git-репозиторії `.gitignore` вже існує — додай до нього відповідні правила, а не замінюй його.

```text
repository/
├── .gitignore
└── setup-manager/
    ├── setup.sh
    ├── config/setup.conf
    ├── modules/
    ├── lib/
    └── ...
```

Після тестів `git status --short`, `git add setup-manager/`, `git commit -m "Release: Setup Manager v1.0.0"`, `git tag -a v1.0.0 -m "Setup Manager v1.0.0"`. У спільному Git-репозиторії перевіряй, чи тег `v1.0.0` ще не існує, та чи інші зміни не потрапили в індекс.

Якщо застосовуєш code-only update до існуючої інсталяції, `config/setup.conf` навмисно не оновлюється. Номер версії `SETUP_VERSION` у своїй інсталяції зміни на `1.0.0` окремо.
