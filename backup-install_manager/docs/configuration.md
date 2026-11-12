# Налаштування

## `config/setup.conf`

```bash
SETUP_KEEP_DAYS=30                      # скільки днів зберігати дані (для операцій очищення)
SETUP_ARCHIVE_PREFIX="dotfiles-backup"  # префікс імен архівних файлів
SETUP_BACKUP_ENABLED=true               # автоматичні захисні копії перед змінами
SETUP_RECOVERY_ENABLED=true             # recovery-знімки файлових операцій
SETUP_LOCK_TIMEOUT=0                    # очікування блокування, с (0–300; 0 — не чекати)
```

`SETUP_KEEP_DAYS` регулює період зберігання для операцій очищення; `SETUP_LOCK_TIMEOUT` — очікування блокування (0–300 с; 0 — без очікування). `SETUP_BACKUP_ENABLED=false` позбавляє операції автоматичної захисної копії; `--sync-delete` при цьому працює, але без відкату. Конфігурація Bash: не додавайте неперевірений код у цей файл.

## `config/packages.conf`

Це INI-реєстр секцій модулів, не виконуваний Bash-код. Порядок секцій визначає поточний порядок встановлення. У наданому архіві: `base`, `cli`, `shell`, `font`, `dev`, `docker`, `network`, `office`, `snapper`, `kde`, `desktop`, `image`, `multimedia`.

```ini
[cli]                       # ім'я модуля; порядок секцій = порядок встановлення
title = CLI                 # людська назва модуля
pacman = neovim kitty fzf   # пакети з офіційного репозиторія
aur =                       # пакети з AUR (порожньо — етап AUR пропускається)
configs = nvim kitty fzf    # імена джерел Dotfiles для застосування конфігів
hooks =                     # загальні hooks модуля
```

Поля: `pacman` (офіційний репозиторій), `aur` (AUR), `configs` (імена Dotfiles), `configs_group` (група), `hooks` (загальні hooks), `hook.ПАКЕТ`, `config.ПАКЕТ`, `depends` (залежності для аналітики `modules plan`). Не додавайте незнайомий пакет або hook без перевірки. Порожній `aur` не повинен показувати етап AUR під час встановлення.

## `config/dotfiles.conf`

Визначає джерела HOME/system, шляхи в репозиторії та групи. Формат полів і валідація залежать від парсера у `src/dotfiles/sources.sh`. При зміні файлу перевіряйте:

```bash
./backup-install_manager.sh sources validate           # перевірка схеми реєстру після редагування
./backup-install_manager.sh sources doctor             # чи існують усі шляхи на диску
./backup-install_manager.sh sources list               # переглянути результат редагування
./backup-install_manager.sh dotfiles plan backup       # план синхронізації без дій
```

Редагуйте користувацькі конфігурації тільки після створення резервної копії. Не підміняйте `config/` або `dotfiles/` при розпакуванні нового релізу.
