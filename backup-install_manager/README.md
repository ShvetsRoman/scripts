# Backup Install Manager v2.0.2

Персональний інсталятор Arch Linux + менеджер dotfiles + бекапи + архіви.

## Швидкий старт

    ./backup-install_manager.sh                    # інтерактивне меню
    ./backup-install_manager.sh sources scan       # подивитись, що є у $HOME
    ./backup-install_manager.sh sources doctor     # перевірити існування
    ./backup-install_manager.sh sources validate   # перевірити схему
    ./backup-install_manager.sh dotfiles backup    # Enter = усі

## Що всередині

  packages    — пакети за config/packages.conf
  dotfiles    — sync HOME ↔ dotfiles за config/dotfiles.conf
  sources     — list / doctor / validate / scan / add / remove
  archive     — tar.gz знімки dotfiles
  recovery    — захист перед кожною зміною
  maintenance — очищення старих backup/логів

## Команди

    ./backup-install_manager.sh packages --list
    ./backup-install_manager.sh packages cli shell
    ./backup-install_manager.sh packages --dry-run all

    ./backup-install_manager.sh dotfiles backup [шлях...]
    ./backup-install_manager.sh dotfiles backup changed [шлях...]
    ./backup-install_manager.sh dotfiles restore [шлях...]
    ./backup-install_manager.sh dotfiles status [шлях...]
    ./backup-install_manager.sh dotfiles verify [шлях...]
    ./backup-install_manager.sh dotfiles plan backup [шлях...]
    ./backup-install_manager.sh dotfiles plan restore [шлях...]
    ./backup-install_manager.sh dotfiles diff [шлях...]

    ./backup-install_manager.sh backup-src SRC REPO_SUB
    ./backup-install_manager.sh restore-src REPO_SUB [TARGET]

    ./backup-install_manager.sh sources list|doctor|scan|add|remove

    ./backup-install_manager.sh archive list|create|restore NAME
    ./backup-install_manager.sh recovery list|verify ID|plan ID|restore ID [REL...]|delete ID
    ./backup-install_manager.sh backups list GROUP
    ./backup-install_manager.sh backups verify GROUP ID
    ./backup-install_manager.sh logs path|tail [N]

    ./backup-install_manager.sh maintenance menu|disk|cleanup TYPE|rotate TYPE KEEP
    ./backup-install_manager.sh doctor
    ./backup-install_manager.sh test

Повний перелік із прикладами — у docs/commands.md.

Актуальні зміни — у docs/CHANGELOG.md.

У Packages реєстр `dotfiles.conf` перевіряється один раз на команду:
`configs_group`, `configs` і `config.<package>` користуються тим самим
перевіреним знімком лише протягом цього виконання. Окремий виклик CLI,
Doctor і команди Dotfiles перечитують конфігурацію, тому постійного кешу немає.

### Кольорові статуси та коди завершення

`dotfiles status`, `dotfiles diff` і `dotfiles verify` завершуються з кодом **0**,
навіть коли файли відрізняються або відсутні; код **2** означає помилку.
`[OK]` — зелений, `[NEW]` (тільки HOME) — блакитний, `[CHANGED]` — жовтий,
`[DEL]` (тільки dotfiles) — червоний. Для вкладених каталогів виводяться
відсутні файли. `[UNTRACKED]` означає, що файл у `dotfiles` не описаний
у `dotfiles.conf`: його HOME-шлях невідомий.

За замовчуванням кольори вмикаються лише в терміналі. `--no-color` або
`NO_COLOR=1` прибирає ANSI; `SETUP_COLOR=always` примусово вмикає їх
для сумісних терміналів.

## Структура проєкту

Увесь програмний код розташовано у `src/` за відповідальністю: `core/`, `cli/`, `packages/`, `dotfiles/`, `recovery/`, `hooks/`, `diagnostics/`.

- `backup-install_manager.sh` — єдина точка входу CLI.
- `hooks/` — тільки функції `hook_main()`, які викликає `src/hooks/hook_runtime.sh`.
- `config/` і `dotfiles/` — користувацькі налаштування та дані.
- `tools/` — інструменти міграції та перевірки захисних копій.
- `tests/` — незалежні Bash-тести; `docs/` — документація.
- `logs/`, `backups/`, `archives/` — локальні runtime-дані, які не входять до релізного архіву.

Повне актуальне дерево: [docs/architecture.md](docs/architecture.md). Зміни структури потребують одночасного оновлення README, architecture.md та CHANGELOG.

## Документація

  docs/commands.md — усі команди
  docs/sources.md  — формат реєстру
  docs/security.md — запобіжники
