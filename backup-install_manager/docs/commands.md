# Повний довідник команд CLI

Усі команди наведені для запуску з кореня проєкту. Джерело переліку — `src/cli/cli.sh` і `--help` наданого архіву.

## Загальні команди

```bash
./backup-install_manager.sh                         # меню
./backup-install_manager.sh --help                  # довідка
./backup-install_manager.sh --version               # версія
./backup-install_manager.sh doctor                  # діагностика
./backup-install_manager.sh test                    # тести
./tests/run-tests.sh                       # тести безпосередньо
```

## Пакети та модулі

```bash
./backup-install_manager.sh packages --list
./backup-install_manager.sh packages cli shell
./backup-install_manager.sh packages --all
./backup-install_manager.sh packages --dry-run all
./backup-install_manager.sh packages --configs-only --sync-delete --yes cli
./backup-install_manager.sh smart --dry-run
./backup-install_manager.sh smart --dry-run cli
./backup-install_manager.sh modules list
./backup-install_manager.sh modules info docker
./backup-install_manager.sh modules deps docker
./backup-install_manager.sh modules reverse base
./backup-install_manager.sh modules stats
./backup-install_manager.sh modules plan
./backup-install_manager.sh report summary
./backup-install_manager.sh report modules
```

`modules plan` показує план залежностей, **не встановлює** модулі та не змінює порядок реального встановлення. Поле `depends` у `packages.conf` використовується для аналізу.

## Dotfiles: HOME ↔ dotfiles

```bash
./backup-install_manager.sh dotfiles status
./backup-install_manager.sh dotfiles status nvim
./backup-install_manager.sh dotfiles verify
./backup-install_manager.sh dotfiles diff nvim
./backup-install_manager.sh dotfiles groups
./backup-install_manager.sh dotfiles status --group cli
./backup-install_manager.sh dotfiles backup
./backup-install_manager.sh dotfiles backup nvim
./backup-install_manager.sh dotfiles backup changed
./backup-install_manager.sh dotfiles backup changed nvim
./backup-install_manager.sh dotfiles restore
./backup-install_manager.sh dotfiles restore nvim
./backup-install_manager.sh dotfiles plan backup
./backup-install_manager.sh dotfiles plan restore
./backup-install_manager.sh dotfiles plan backup --group cli
```

Фільтр `[ШЛЯХ...]` допускає імена джерел або їхні шляхи, зареєстровані в `dotfiles.conf`. `--group ГРУПА` обмежує операцію групою. `status`, `verify`, `diff` повертають 0 для звичайних розбіжностей та 2 для помилок перевірки. `[OK]` — однаково, `[CHANGED]` — відрізняється, `[NEW]` — лише HOME, `[DEL]` — лише репозиторій, `[UNTRACKED]` — не описано у реєстрі. `status` не очищає Kitty scrollback.

## Довільні джерела та реєстр

```bash
./backup-install_manager.sh backup-src "$HOME/Documents/example" home/Documents/example
./backup-install_manager.sh restore-src home/Documents/example "$HOME/Documents/example"
./backup-install_manager.sh sources list
./backup-install_manager.sh sources doctor
./backup-install_manager.sh sources validate
./backup-install_manager.sh sources scan
./backup-install_manager.sh sources add example home '~/Documents/example' personal
./backup-install_manager.sh sources remove example
```

Для `sources add` формат: `NAME TYPE PATH GROUP`. `TYPE` — `home`, `system` або порожній тип для абсолютного шляху. Перевіряйте результат `sources list` після редагування реєстру.

## Архіви та відновлення

```bash
./backup-install_manager.sh archive list
./backup-install_manager.sh archive create
./backup-install_manager.sh archive restore ІМʼЯ
./backup-install_manager.sh recovery list
./backup-install_manager.sh recovery verify ID
./backup-install_manager.sh recovery plan ID
./backup-install_manager.sh recovery plan ID ШЛЯХ
./backup-install_manager.sh recovery restore ID
./backup-install_manager.sh recovery restore ID ШЛЯХ
./backup-install_manager.sh recovery delete ID
./backup-install_manager.sh backups list dotfiles
./backup-install_manager.sh backups verify dotfiles ID
```

`recovery verify` перевіряє manifest і контрольні суми, якщо вони наявні. Код 3 для legacy-резервної копії означає, що її цілісність не може бути підтверджена за новою схемою.

## Обслуговування, логи, оновлення

```bash
./backup-install_manager.sh maintenance menu
./backup-install_manager.sh maintenance disk
./backup-install_manager.sh maintenance cleanup logs
./backup-install_manager.sh maintenance rotate dotfiles 10
./backup-install_manager.sh logs path
./backup-install_manager.sh logs tail
./backup-install_manager.sh logs tail 100
./backup-install_manager.sh update /шлях/до/release.tar.gz --dry-run
./backup-install_manager.sh update /шлях/до/release.tar.gz --sha256 SHA256
```

У `update` перевірте формат очікуваного архіву та SHA-256 перед реальним застосуванням. `maintenance cleanup`/`rotate` можуть видаляти старі дані; спочатку перевірте dry-run.

## Прапорці

| Прапорець | Значення |
|---|---|
| `--dry-run` | показати заплановане без застосування, де підтримується |
| `--yes`, `-y` | пропуск підтверджень |
| `--no-color` | без ANSI-кольорів |
| `--verbose`, `-v` | додаткова діагностика |
| `--sync-delete` | видаляти зайве на цільовій стороні синхронізації |
| `--no-backup` | вимкнути захисне копіювання; ризик при помилці |
| `--configs-only` | тільки конфігурації у Packages |
| `--no-configs` | не застосовувати конфігурації у Packages |
| `--strict-configs` | сувора перевірка конфігурацій |
| `--all` | усі модулі Packages |

Глобальні прапорці можуть стояти до або після команди; параметри на кшталт `--group` обробляються відповідною підкомандою. Не всі прапорці мають сенс для кожної команди.

## Запуск з кореня проєкту

```bash
cd ~/Documents/backup-install_manager
./backup-install_manager.sh --help
./backup-install_manager.sh --version
./tests/run-tests.sh
```

> Доступні дії перевіряйте через `--help`. Операції `restore`, `update`, `packages`, `cleanup` можуть змінювати файли або систему.
