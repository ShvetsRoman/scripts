# Installer Packages V1.6

Модульний installer для Arch Linux.

Основні можливості:

- pacman packages;
- AUR packages через `paru` з автоматичною перевіркою/встановленням paru;
- зовнішні install-script/GitHub packages із `config/packages.conf`;
- конфіги з `../dotfiles-manager/dotfiles`;
- backup перед заміною конфігів;
- systemd services;
- post-install hooks;
- `Status` і `Verify`;
- `--dry-run`;
- logs;
- меню очищення backups/logs;
- динамічне меню модулів.

## Запуск

```bash
./install.sh
```

Один модуль:

```bash
./install.sh cli
```

Кілька модулів:

```bash
./install.sh cli shell dev
```

Усе:

```bash
./install.sh all
```

Dry-run:

```bash
./install.sh --dry-run all
```

Help:

```bash
./install.sh --help
```

## Status / Verify

```bash
./install.sh status all
./install.sh verify all
```

`Status` показує поточний стан. `Verify` є строгою перевіркою і повертає exit code `1`, якщо знайдено невідповідності.

## Конфіги

Формат у `config/configs.conf`:

```bash
[ID]="MODULE|SCOPE|SOURCE|DESTINATION"
```

Наприклад:

```bash
[superfile]="cli|home|.config/superfile|.config/superfile"
```

## Зовнішні / GitHub packages

У `config/packages.conf` зовнішні програми описуються в одному registry:

```bash
CLI_GITHUB_PACKAGES=(
    superfile
)

declare -Ag GITHUB_PACKAGES=(
    [superfile]="script|https://superfile.dev/install.sh|spf"

    # git repository:
    # [my-git-tool]="git|https://github.com/user/repo.git|mytool|~/.local/share/mytool|bin/mytool"

    # готовий binary:
    # [my-binary]="binary|https://github.com/user/repo/releases/download/v1.0/mytool|mytool|~/.local/bin/mytool"
)
```

Підтримуються три типи:

- `script|URL|CHECK_COMMAND` — завантажити install script через `curl` і виконати через `bash`;
- `git|REPOSITORY_URL|CHECK_COMMAND|DEST_DIR|EXECUTABLE_REL` — клонувати repository, зробити executable виконуваним і створити symlink у `~/.local/bin`;
- `binary|BINARY_URL|CHECK_COMMAND|DEST_FILE` — завантажити готовий executable та встановити його у вказаний шлях.

Прив'язка масиву до модуля у `config/modules.conf`:

```bash
MODULE_GITHUB_ARRAYS[cli]="CLI_GITHUB_PACKAGES"
```

`Status` і `Verify` використовують `CHECK_COMMAND`, тому працюють однаково для всіх трьох типів.

## Paru

Якщо модуль містить AUR packages, installer автоматично перевіряє `paru`. Якщо `paru` відсутній, встановлюються `base-devel` і `git`, після чого `paru` збирається з AUR.

## Network

Модуль `network` після встановлення `openssh` автоматично виконує:

```bash
sudo systemctl enable --now sshd
```

## Backup

```text
backups/YYYY-MM-DD_HH-MM-SS/
```

`--no-backup` повністю вимикає створення backup.

## Logs

```text
log/run-YYYY-MM-DD_HH-MM-SS.log
```

## Обслуговування

Через меню доступно:

1. Видалити всі backups
2. Залишити останні 3 backups
3. Видалити backups старші за 30 днів
4. Видалити всі logs
5. Залишити останні 10 logs
6. Видалити logs старші за 30 днів

## Додавання нового модуля

Дивись `docs/ADDING_MODULE.md`.
