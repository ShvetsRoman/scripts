# Installer Packages V2.0

Модульний інсталятор **Arch Linux** із єдиним `.sh` файлом для кожного модуля (Unified Modules).
Усі коментарі та інструкції — українською мовою.

## Найголовніше

Для додавання пакета або його конфігу редагуйте **лише** `modules/НАЗВА.sh`.
Автоматичний реєстр `lib/registry.sh` сформує списки pacman, AUR, GitHub, налаштувань, сервісів та залежностей. Старі `config/packages.conf`, `config/modules.conf`, `config/configs.conf` вилучені.

## Запуск

```bash
chmod +x install.sh
./install.sh --list
./install.sh --list-configs
./install.sh --dry-run cli shell
./install.sh cli
./install.sh --yes cli shell
./install.sh --configs-only cli
./install.sh --no-configs docker
./install.sh status all
./install.sh verify cli
./install.sh
```

Запускайте **без sudo** (для привілейованих дій скрипт використовує `sudo`). Підтримуються `--no-backup`, `--strict-configs`, `--sync-delete`, `--no-deps`. `--sync-delete` може видаляти файли у призначенні. `--yes` підтверджує операції пакетного менеджера, не робить неперевірені зовнішні джерела безпечними.

## Додавання pacman / AUR пакета

Відкрийте `modules/cli.sh`:

```bash
PACMAN_PACKAGES=(
    bat
    neovim
    yazi  # нова програма
)
AUR_PACKAGES=(
    # назви AUR-пакетів
)
```

Не потрібно реєструвати пакет у жодному іншому файлі.

## Додавання конфігу

Конфіги беруться із `DOTFILES_DIR`, який визначено в `config/installer.conf`. Типовий шлях — `../dotfiles-manager/dotfiles`.

```bash
CONFIG_ITEMS=(
    "yazi|home|.config/yazi|.config/yazi"
)
```

Формат: `ID|SCOPE|SOURCE|DESTINATION`. `home` — шлях призначення відносно `$HOME`; `system` — абсолютний шлях. Для одного модуля можна задати кілька конфігів. Відсутнє джерело попереджає, а з `--strict-configs` є помилкою. Під час копіювання можливо резервне збереження старої конфігурації.

## Зовнішня програма

У `GITHUB_ITEMS` модуля додайте рядок `ID|TYPE|URL|CHECK_COMMAND` (для `git` і `binary` потрібні додаткові поля, див. `docs/ADDING_MODULE.md`). Тип `script` завантажує та виконує сторонній код; використовувати тільки перевірені джерела, краще зафіксовані версії та перевірені контрольні суми. У проєкті збережено попередній спосіб встановлення Superfile.

## Новий модуль

Створіть `modules/mytools.sh` за зразком `templates/module.sh`. Назва файла має дорівнювати `MODULE_ID`. Порядок у меню задає `MODULE_ORDER`. Не потрібно редагувати `lib/` або UI. Для нестандартного post-install hook оголосіть функцію в тому ж `modules/mytools.sh` та задайте її ім’я в `MODULE_POST_HOOK`.

## Hooks

`modules/shell.sh` містить пакети та налаштування shell, `modules/docker.sh` — додавання користувача до групи Docker. Відповідна назва функції задається в цьому ж `.sh`. Зміна shell для root і членство у docker-групі — привілейовані операції, оцінюйте їх перед запуском.

## Перевірки

```bash
bash tests/run-tests.sh
bash -n install.sh
shellcheck install.sh lib/*.sh modules/*.sh  # якщо ShellCheck встановлено
```

Тести не встановлюють пакети й не змінюють системні конфіги. Повне встановлення в реальній системі цими тестами не перевіряється.

## Де що змінювати

- `modules/*.sh` — **єдиний файл модуля**: пакети, конфіги, сервіси, залежності й необов’язковий hook.
- `config/installer.conf` — глобальні шляхи, поведінка backup та log.
- `lib/` — механізм, редагувати для звичайних програм не потрібно.
- `tests/` — перевірки механізму і структури.

Порада: перш ніж запускати реальне встановлення, виконайте `--list`, `--list-configs`, `--dry-run`, а для налаштувань з `--sync-delete` перевірте файли призначення вручну.

## Безпека та особливості єдиного файла

Усі `modules/*.sh` підключаються через `source` під час старту інсталятора (навіть при `--list`). Тому на верхньому рівні файлів дозволені лише оголошення змінних, масивів та функцій; **ніяких команд встановлення або зміни системи поза функцією hook**. `MODULE_POST_HOOK` запускається тільки після стандартних дій відповідного модуля. Обов’язково перевіряйте сторонній код.
