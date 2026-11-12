# Повний довідник команд CLI

Усі команди наведені для запуску з кореня проєкту. Джерело переліку — `src/cli/cli.sh` і `--help` наданого архіву.

> **Де запускати.** Корінь проєкту — це каталог, де лежить `backup-install_manager.sh` (у цьому середовищі: `~/00_setup/scripts_bash/backup-install_manager`).

## Загальні команди

```bash
./backup-install_manager.sh                    # інтерактивне меню
./backup-install_manager.sh --help             # довідка по всіх командах
./backup-install_manager.sh --version          # версія (читається з src/core/version.sh)
./backup-install_manager.sh doctor             # діагностика середовища
./backup-install_manager.sh test               # тести через CLI
./tests/run-tests.sh                           # тести напряму, без CLI
```

## Пакети та модулі

```bash
./backup-install_manager.sh packages --list                                   # перелік пакетів без встановлення
./backup-install_manager.sh packages cli shell                                # встановити пакети модулів cli і shell
./backup-install_manager.sh packages --all                                    # усі модулі реєстру
./backup-install_manager.sh packages --dry-run all                            # сухий прогін: показати план без дій
./backup-install_manager.sh packages --configs-only --sync-delete --yes cli   # лише конфігурації, з видаленням зайвого
./backup-install_manager.sh smart --dry-run                                   # «розумний» прогін, спершу без дій
./backup-install_manager.sh smart --dry-run cli                               # те саме, обмежене модулем cli
./backup-install_manager.sh modules list                                      # перелік модулів
./backup-install_manager.sh modules info docker                               # вміст модуля docker
./backup-install_manager.sh modules deps docker                               # від кого залежить docker
./backup-install_manager.sh modules reverse base                              # хто залежить від base
./backup-install_manager.sh modules stats                                     # статистика графа модулів
./backup-install_manager.sh modules plan                                      # план залежностей (не встановлює)
./backup-install_manager.sh report summary                                    # короткий звіт
./backup-install_manager.sh report modules                                    # звіт по модулях
```

`modules plan` показує план залежностей, **не встановлює** модулі та не змінює порядок реального встановлення. Поле `depends` у `packages.conf` використовується для аналізу.

## Dotfiles: HOME ↔ dotfiles

```bash
./backup-install_manager.sh dotfiles status                    # порівняти HOME і dotfiles (лише читання)
./backup-install_manager.sh dotfiles status nvim               # статус одного джерела
./backup-install_manager.sh dotfiles verify                    # перевірка розбіжностей
./backup-install_manager.sh dotfiles diff nvim                 # пофайлові відмінності
./backup-install_manager.sh dotfiles groups                    # перелік груп реєстру
./backup-install_manager.sh dotfiles status --group cli        # статус лише групи cli
./backup-install_manager.sh dotfiles backup                    # скопіювати HOME → dotfiles (Enter = усі)
./backup-install_manager.sh dotfiles backup nvim               # скопіювати одне джерело
./backup-install_manager.sh dotfiles backup changed            # лише змінені файли
./backup-install_manager.sh dotfiles backup changed nvim       # лише змінені в одному джерелі
./backup-install_manager.sh dotfiles restore                   # відновити dotfiles → HOME
./backup-install_manager.sh dotfiles restore nvim              # відновити одне джерело
./backup-install_manager.sh dotfiles plan backup               # що зробить backup (без дій)
./backup-install_manager.sh dotfiles plan restore              # що зробить restore (без дій)
./backup-install_manager.sh dotfiles plan backup --group cli   # план лише для групи cli
```

Фільтр `[ШЛЯХ...]` допускає імена джерел або їхні шляхи, зареєстровані в `dotfiles.conf`. `--group ГРУПА` обмежує операцію групою. `status`, `verify`, `diff` повертають 0 для звичайних розбіжностей та 2 для помилок перевірки. `[OK]` — однаково, `[CHANGED]` — відрізняється, `[NEW]` — лише HOME, `[DEL]` — лише репозиторій, `[UNTRACKED]` — не описано у реєстрі. `status` не очищає Kitty scrollback.

## Довільні джерела та реєстр

```bash
./backup-install_manager.sh backup-src "$HOME/Documents/example" home/Documents/example   # разовий бекап довільного шляху
./backup-install_manager.sh restore-src home/Documents/example "$HOME/Documents/example"  # повернути його назад
./backup-install_manager.sh sources list          # поточний реєстр джерел
./backup-install_manager.sh sources doctor        # чи існують шляхи на диску
./backup-install_manager.sh sources validate      # перевірка схеми реєстру
./backup-install_manager.sh sources scan          # що є у $HOME поза реєстром
./backup-install_manager.sh sources add example home '~/Documents/example' personal   # додати запис NAME TYPE PATH GROUP
./backup-install_manager.sh sources remove example                                    # видалити запис із реєстру
```

Для `sources add` формат: `NAME TYPE PATH GROUP`. `TYPE` — `home`, `system` або порожній тип для абсолютного шляху. Перевіряйте результат `sources list` після редагування реєстру.

## Архіви та відновлення

```bash
./backup-install_manager.sh archive list              # перелік архівів dotfiles/
./backup-install_manager.sh archive create            # створити архів каталогу dotfiles/
./backup-install_manager.sh archive restore ІМʼЯ      # відновити архів за ім'ям
./backup-install_manager.sh recovery list             # перелік захисних знімків
./backup-install_manager.sh recovery verify ID        # перевірка manifest і контрольних сум
./backup-install_manager.sh recovery plan ID          # що буде відновлено (без дій)
./backup-install_manager.sh recovery plan ID ШЛЯХ     # план для окремого файла
./backup-install_manager.sh recovery restore ID       # реальне відновлення знімка
./backup-install_manager.sh recovery restore ID ШЛЯХ  # відновити лише один файл
./backup-install_manager.sh recovery delete ID        # видалити знімок (незворотно)
./backup-install_manager.sh backups list dotfiles     # резервні копії групи dotfiles
./backup-install_manager.sh backups verify dotfiles ID    # перевірка цілісності резервної копії
```

`recovery verify` перевіряє manifest і контрольну суму, якщо вони наявні. Код 3 для legacy-резервної копії означає, що її цілісність не може бути підтверджена за новою схемою.

## Обслуговування, логи, оновлення

```bash
./backup-install_manager.sh maintenance menu                  # меню обслуговування
./backup-install_manager.sh maintenance disk                  # огляд зайнятого місця
./backup-install_manager.sh maintenance cleanup logs          # очищення старих логів
./backup-install_manager.sh maintenance rotate dotfiles 10    # залишити 10 копій групи dotfiles
./backup-install_manager.sh logs path                         # шлях до поточного журналу
./backup-install_manager.sh logs tail                         # останні рядки журналу
./backup-install_manager.sh logs tail 100                     # останні 100 рядків
./backup-install_manager.sh update /шлях/до/release.tar.gz --dry-run      # оновлення: спершу сухий прогін
./backup-install_manager.sh update /шлях/до/release.tar.gz --sha256 SHA256    # оновлення з контролем хешу
```

У `update` перевірте формат очікуваного архіву та SHA-256 перед реальним застосуванням. `maintenance cleanup`/`rotate` можуть видаляти старі дані; спочатку перевірте dry-run.

## Прапорці

| Прапорець | Значення |
|---|---|
| `--dry-run` | показати заплановане без застосування, де підтримується |
| `--yes`, `-y` | пропуск підтверджень |
| `--no-color` | без ANSI-кольорів |
| `--verbose`, `-v` | додаткова діагностика |
| `--sync-delete` | видаляти зайве на цільовій стороні синхронізації (дозволено і без захисних копій — тоді відкат недоступний) |
| `--no-backup` | вимкнути захисне копіювання; ризик при помилці |
| `--configs-only` | тільки конфігурації у Packages |
| `--no-configs` | не застосовувати конфігурації у Packages |
| `--strict-configs` | сувора перевірка конфігурацій |
| `--all` | усі модулі Packages |

Глобальні прапорці можуть стояти до або після команди; параметри на кшталт `--group` обробляються відповідною підкомандою. Не всі прапорці мають сенс для кожної команди.

## Запуск з кореня проєкту

```bash
cd /шлях/до/backup-install_manager    # корінь проєкту, напр. ~/00_setup/scripts_bash/backup-install_manager
./backup-install_manager.sh --help
./backup-install_manager.sh --version
./tests/run-tests.sh
```

> Доступні дії перевіряйте через `--help`. Операції `restore`, `update`, `packages`, `cleanup` можуть змінювати файли або систему.
