# Додавання нового модуля — Installer Packages V1.6

У V1.6 меню, Status, Verify та встановлення модулів працюють через metadata.
Для нового модуля зазвичай потрібно змінити 4 файли:

- `config/packages.conf`
- `config/modules.conf`
- `config/configs.conf`
- `modules/<module>.sh`

## 1. Пакети pacman

У `config/packages.conf`:

```bash
MYMODULE_PACKAGES=(
    package1
    package2
)
```

## 2. AUR-пакети

Якщо потрібні AUR-пакети:

```bash
MYMODULE_AUR_PACKAGES=(
    aur-package1
)
```

`paru` перевіряється автоматично. Якщо його немає, installer встановить `base-devel` і `git`, збере `paru` з AUR і продовжить встановлення.

Якщо AUR-пакетів немає, окремий порожній масив створювати не потрібно — у `MODULE_AUR_ARRAYS` достатньо `""`.

## 3. Зовнішні / GitHub програми

Усі зовнішні джерела описуються в `config/packages.conf`.

Спочатку створити список ID для модуля:

```bash
MYMODULE_GITHUB_PACKAGES=(
    superfile
    my-git-tool
    my-binary
)
```

Потім додати записи у registry `GITHUB_PACKAGES`.

### TYPE=script

```bash
[superfile]="script|https://superfile.dev/install.sh|spf"
```

Формат:

```text
ID="script|URL|CHECK_COMMAND"
```

Installer завантажить script через `curl -fsSL` і виконає його через `bash`.

### TYPE=git

```bash
[my-git-tool]="git|https://github.com/user/repo.git|mytool|~/.local/share/mytool|bin/mytool"
```

Формат:

```text
ID="git|REPOSITORY_URL|CHECK_COMMAND|DEST_DIR|EXECUTABLE_REL"
```

Installer:

1. клонує repository в `DEST_DIR`;
2. при повторному запуску виконує `git pull --ff-only`;
3. робить `DEST_DIR/EXECUTABLE_REL` виконуваним;
4. створює symlink `~/.local/bin/CHECK_COMMAND`.

### TYPE=binary

```bash
[my-binary]="binary|https://github.com/user/repo/releases/download/v1.0/mytool|mytool|~/.local/bin/mytool"
```

Формат:

```text
ID="binary|BINARY_URL|CHECK_COMMAND|DEST_FILE"
```

Installer завантажує файл через `curl`, встановлює права `755` і переносить його у `DEST_FILE`. Для `/usr/*` та `/opt/*` автоматично використовується `sudo`.

`CHECK_COMMAND` використовується для перевірки встановлення, `Status` і `Verify`.

## 4. Реєстрація модуля

У `config/modules.conf` додати модуль до `MODULES`:

```bash
MODULES=(
    ...
    mymodule
)
```

Назва:

```bash
MODULE_TITLES[mymodule]="My Module"
```

Залежності:

```bash
MODULE_DEPENDENCIES[mymodule]="base"
```

Pacman-масив:

```bash
MODULE_PACMAN_ARRAYS[mymodule]="MYMODULE_PACKAGES"
```

AUR-масив:

```bash
MODULE_AUR_ARRAYS[mymodule]="MYMODULE_AUR_PACKAGES"
```

або без AUR:

```bash
MODULE_AUR_ARRAYS[mymodule]=""
```

Зовнішні install-script packages:

```bash
MODULE_GITHUB_ARRAYS[mymodule]="MYMODULE_GITHUB_PACKAGES"
```

або:

```bash
MODULE_GITHUB_ARRAYS[mymodule]=""
```

Сервіси:

```bash
MODULE_SERVICES[mymodule]="myservice"
```

Post-install hook:

```bash
MODULE_POST_HOOKS[mymodule]=""
```

або:

```bash
MODULE_POST_HOOKS[mymodule]="configure_something"
```

## 5. Конфігурації

`MODULE_CONFIGS` вручну не заповнюється. Він генерується автоматично з `CONFIG_MAP`.

У `config/configs.conf`:

```bash
[myconfig]="mymodule|home|.config/myapp|.config/myapp"
```

Формат:

```text
[ID]="MODULE|SCOPE|SOURCE|DESTINATION"
```

Для системного файлу:

```bash
[my-system-config]="mymodule|system|etc/myapp/config.conf|/etc/myapp/config.conf"
```

## 6. Файл модуля

Створити `modules/mymodule.sh`:

```bash
#!/usr/bin/env bash

install_module() {
    install_registered_module "mymodule"
}
```

`install_registered_module` автоматично виконає:

1. pacman packages;
2. AUR packages через paru;
3. зовнішні/GitHub/install-script packages;
4. configs;
5. systemd services;
6. post-install hook.

## 7. Перевірка

```bash
./tests/run-tests.sh
./install.sh --dry-run mymodule
./install.sh status mymodule
./install.sh verify mymodule
```

## Приклад: Superfile у CLI

`config/packages.conf`:

```bash
CLI_GITHUB_PACKAGES=(
    superfile
)

declare -Ag GITHUB_PACKAGES=(
    [superfile]="script|https://superfile.dev/install.sh|spf"
)
```

`config/modules.conf`:

```bash
MODULE_GITHUB_ARRAYS[cli]="CLI_GITHUB_PACKAGES"
```

`config/configs.conf`:

```bash
[superfile]="cli|home|.config/superfile|.config/superfile"
```

Тоді `./install.sh cli` встановить Superfile та скопіює його конфіг із `dotfiles-manager`.
