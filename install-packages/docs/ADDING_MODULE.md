# Додавання нового модуля — Installer Packages V1.5

У V1.5 меню, `all`, multi-select, `status`, `verify`, пакети, AUR, сервіси та post-install hooks керуються metadata. `MODULE_CONFIGS` вручну більше не створюється — він автоматично будується з `CONFIG_MAP`.

Нижче приклад нового модуля `graphics`.

## 1. Додай пакети в `config/packages.conf`

Pacman:

```bash
GRAPHICS_PACKAGES=(
    gimp
    inkscape
    imagemagick
)
```

AUR, якщо потрібен:

```bash
GRAPHICS_AUR_PACKAGES=(
    some-aur-package
)
```

Якщо AUR-пакетів немає, масив створювати не потрібно.

## 2. Зареєструй модуль у `config/modules.conf`

Додай `graphics` у `MODULES`:

```bash
MODULES=(
    base
    cli
    shell
    dev
    docker
    network
    desktop
    multimedia
    graphics
)
```

Додай metadata:

```bash
MODULE_TITLES[graphics]="Graphics"
MODULE_DEPENDENCIES[graphics]="base"
MODULE_PACMAN_ARRAYS[graphics]="GRAPHICS_PACKAGES"
MODULE_AUR_ARRAYS[graphics]="GRAPHICS_AUR_PACKAGES"
MODULE_SERVICES[graphics]=""
MODULE_POST_HOOKS[graphics]=""
```

Якщо pacman або AUR пакетів немає:

```bash
MODULE_PACMAN_ARRAYS[graphics]=""
MODULE_AUR_ARRAYS[graphics]=""
```

Кілька залежностей або сервісів записуються через пробіл.

## 3. Додай конфіги в `config/configs.conf`

Формат V1.5:

```text
[ID]="MODULE|SCOPE|SOURCE|DESTINATION"
```

Користувацький конфіг:

```bash
CONFIG_MAP[graphics-app]="graphics|home|.config/graphics-app|.config/graphics-app"
```

Системний конфіг:

```bash
CONFIG_MAP[graphics-system]="graphics|system|etc/graphics/app.conf|/etc/graphics/app.conf"
```

На цьому все. Запис на кшталт:

```bash
MODULE_CONFIGS[graphics]="graphics-app graphics-system"
```

**більше не потрібен**. `build_module_configs()` сам збере всі записи `CONFIG_MAP`, у яких перше поле дорівнює `graphics`.

Якщо модуль не має конфігів — у `configs.conf` для нього взагалі нічого додавати не потрібно.

## 4. Створи `modules/graphics.sh`

```bash
#!/usr/bin/env bash

install_module() {
    install_registered_module graphics
}
```

Стандартний runner сам:

1. встановить pacman-пакети;
2. встановить AUR-пакети;
3. скопіює всі конфіги, автоматично знайдені через `CONFIG_MAP`;
4. увімкне systemd-сервіси;
5. запустить post-install hook.

## 5. Необов'язковий post-install hook

```bash
configure_graphics() {
    log_step "Додаткове налаштування Graphics."
    run_cmd some-command --example
}

install_module() {
    install_registered_module graphics
}
```

У `config/modules.conf`:

```bash
MODULE_POST_HOOKS[graphics]="configure_graphics"
```

Для команд усередині hook використовуй `run_cmd`, щоб `--dry-run` працював автоматично.

## 6. Що НЕ потрібно змінювати

Не редагуй:

```text
install.sh
lib/ui.sh
lib/status.sh
lib/package-manager.sh
lib/modules.sh
```

Меню та службові команди підхоплять модуль автоматично.

## 7. Перевірка

```bash
./tests/run-tests.sh
./install.sh --list
./install.sh --list-configs
./install.sh --dry-run graphics
./install.sh status graphics
./install.sh verify graphics
```

## Короткий чекліст

Для нового модуля зазвичай змінюються тільки:

1. `config/packages.conf`
2. `config/modules.conf`
3. `config/configs.conf` — тільки якщо є конфіги
4. `modules/<module>.sh`

`MODULE_CONFIGS` у V1.5 вручну не редагується.
