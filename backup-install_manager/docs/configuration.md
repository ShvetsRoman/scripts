# Налаштування

## `config/setup.conf`

```bash
SETUP_KEEP_DAYS=30
SETUP_ARCHIVE_PREFIX="dotfiles-backup"
SETUP_BACKUP_ENABLED=true
SETUP_RECOVERY_ENABLED=true
SETUP_LOCK_TIMEOUT=0
```

`SETUP_KEEP_DAYS` регулює період зберігання для операцій очищення; `SETUP_LOCK_TIMEOUT` — очікування блокування (0–300 с; 0 — без очікування). `SETUP_BACKUP_ENABLED=false` позбавляє операції автоматичної захисної копії; використовуйте обережно. Конфігурація Bash: не додавайте неперевірений код у цей файл.

## `config/packages.conf`

Це INI-реєстр секцій модулів, не виконуваний Bash-код. Порядок секцій визначає поточний порядок встановлення. У наданому архіві: `base`, `cli`, `shell`, `font`, `dev`, `docker`, `network`, `office`, `snapper`, `kde`, `desktop`, `image`, `multimedia`.

```ini
[cli]
title = CLI
pacman = neovim kitty fzf
aur =
configs = nvim kitty fzf
hooks =
```

Поля: `pacman` (офіційний репозиторій), `aur` (AUR), `configs` (імена Dotfiles), `configs_group` (група), `hooks` (загальні hooks), `hook.ПАКЕТ`, `config.ПАКЕТ`, `depends` (залежності для аналітики `modules plan`). Не додавайте незнайомий пакет або hook без перевірки. Порожній `aur` не повинен показувати етап AUR під час встановлення.

## `config/dotfiles.conf`

Визначає джерела HOME/system, шляхи в репозиторії та групи. Формат полів і валідація залежать від парсера у `src/dotfiles/sources.sh`. При зміні файлу перевіряйте:

```bash
./backup-install_manager.sh sources validate
./backup-install_manager.sh sources doctor
./backup-install_manager.sh sources list
./backup-install_manager.sh dotfiles plan backup
```

Редагуйте користувацькі конфігурації тільки після створення резервної копії. Не підміняйте `config/` або `dotfiles/` при розпакуванні нового релізу.
