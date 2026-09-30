# Installer Packages V1.5

Модульний installer для Arch Linux, який:

- встановлює пакети через `pacman` і `paru`;
- автоматично вирішує залежності модулів;
- копіює готові конфіги з `../dotfiles-manager/dotfiles`;
- робить backup існуючих конфігів;
- підтримує `status`, `verify`, `--dry-run`, `--configs-only`, `--no-configs`;
- має динамічне меню;
- підтримує systemd services і post-install hooks.

## Головні зміни V1.5

### 1. `MODULE_CONFIGS` більше не заповнюється вручну

Формат `CONFIG_MAP` тепер:

```bash
[ID]="MODULE|SCOPE|SOURCE|DESTINATION"
```

Наприклад:

```bash
[nvim]="cli|home|.config/nvim|.config/nvim"
[kitty]="cli|home|.config/kitty|.config/kitty"
[starship]="shell|home|.config/starship|.config/starship"
```

Під час запуску `build_module_configs()` автоматично формує:

```text
cli   -> kitty nvim wezterm
shell -> starship zsh zsh-alias zsh-path
```

Тому окремий ручний блок `MODULE_CONFIGS=(...)` більше не потрібний.

### 2. Стабільний формат виводу

Логічні блоки в терміналі розділені порожніми рядками:

```text
[INFO] Порядок виконання: base cli shell ...

[STEP] Запуск модуля: base
...

[STEP] Встановлення pacman-пакетів:
...

[OK] Модуль завершено: base

[STEP] Запуск модуля: cli
```

Так само окремо відділяються блоки конфігів, backup і post-install hooks.

### 3. Starship копіюється як каталог

```bash
[starship]="shell|home|.config/starship|.config/starship"
```

Тобто:

```text
source:      dotfiles-manager/dotfiles/.config/starship/
destination: ~/.config/starship/
backup:      ~/.config/starship
```

### 4. Канонічний шлях Zsh

Shell hook використовує `readlink -f`, тому на Arch `/sbin/zsh` нормалізується до `/usr/bin/zsh` перед записом у `/etc/shells` та викликом `chsh`.

## Очікувана структура

```text
scripts_bash/
├── dotfiles-manager/
│   └── dotfiles/
└── installer-packages/
    ├── install.sh
    ├── backups/
    ├── config/
    │   ├── installer.conf
    │   ├── packages.conf
    │   ├── modules.conf
    │   └── configs.conf
    ├── lib/
    ├── modules/
    ├── docs/
    │   └── ADDING_MODULE.md
    ├── templates/
    │   └── module.sh
    └── tests/
        └── run-tests.sh
```

## Поточні конфіги

```bash
declare -Ag CONFIG_MAP=(
    [nvim]="cli|home|.config/nvim|.config/nvim"
    [kitty]="cli|home|.config/kitty|.config/kitty"
    [wezterm]="cli|home|.config/wezterm|.config/wezterm"

    [zsh]="shell|home|.zshrc|.zshrc"
    [zsh-alias]="shell|home|.zsh_alias.zsh|.zsh_alias.zsh"
    [zsh-path]="shell|home|.zsh_path.zsh|.zsh_path.zsh"
    [starship]="shell|home|.config/starship|.config/starship"
)
```

## Основні команди

```bash
./install.sh
./install.sh shell
./install.sh cli shell dev
./install.sh all

./install.sh --dry-run shell
./install.sh --dry-run all
./install.sh -y all

./install.sh --configs-only shell
./install.sh --no-configs shell
./install.sh --no-backup shell
./install.sh --strict-configs shell
./install.sh --sync-delete cli

./install.sh status shell
./install.sh status all
./install.sh verify shell
./install.sh verify all

./install.sh --list
./install.sh --list-configs
```

## Backup конфігів

За замовчуванням backup створюється в:

```text
installer-packages/backups/YYYY-MM-DD_HH-MM-SS/
```

Backup робиться саме для destination конкретного конфігу, а не для всього `~/.config`.

Наприклад Starship:

```text
~/.config/starship
```

а не:

```text
~/.config
```

## Додавання нового модуля

Повна інструкція:

```text
docs/ADDING_MODULE.md
```

Шаблон:

```text
templates/module.sh
```

## Тести

```bash
./tests/run-tests.sh
```

Тести перевіряють синтаксис, metadata, автоматичну генерацію `MODULE_CONFIGS`, config mapping, dependency resolver, динамічне меню, post-install hooks, Shell dry-run, формат версії та ShellCheck, якщо він встановлений.
