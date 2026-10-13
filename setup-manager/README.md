# Setup Manager V1

Персональний інсталятор Arch Linux + менеджер dotfiles + бекапи + архіви.

## Швидкий старт

    ./setup.sh                    # інтерактивне меню
    ./setup.sh sources scan       # подивитись, що є у $HOME
    ./setup.sh sources doctor     # перевірити існування
    ./setup.sh dotfiles backup    # Enter = усі

## Що всередині

  installer   — пакети за modules/*.sh
  dotfiles    — sync HOME ↔ dotfiles за config/sources.conf
  sources     — list / doctor / scan / seed / add / remove
  archive     — tar.gz знімки dotfiles
  recovery    — захист перед кожною зміною
  maintenance — очищення старих backup/логів

## Команди

    ./setup.sh installer --list
    ./setup.sh installer cli shell
    ./setup.sh installer --dry-run all

    ./setup.sh dotfiles backup [шлях...]
    ./setup.sh dotfiles restore [шлях...]
    ./setup.sh dotfiles status
    ./setup.sh dotfiles diff [шлях...]

    ./setup.sh backup-src SRC REPO_SUB
    ./setup.sh restore-src REPO_SUB [TARGET]

    ./setup.sh sources list|doctor|scan|seed|add|remove

    ./setup.sh archive list|create|restore NAME
    ./setup.sh recovery list|restore ID|delete ID

    ./setup.sh maintenance menu|disk|cleanup TYPE
    ./setup.sh doctor
    ./setup.sh test

Повний перелік із прикладами — у docs/commands.md.

## Структура

    config/     setup.conf, sources.conf
    lib/        ядро (ui, path, fs, apply, sources, sync, ...)
    modules/    декларативні модулі пакетів
    tools/      archive_safe.py, update_safe.py
    tests/      синтаксис + базові перевірки
    docs/       документація
    dotfiles/   репозиторій конфігів
    backups/    захист + recovery
    archives/   tar.gz знімки
    logs/       журнали

## Документація

  docs/commands.md — усі команди
  docs/sources.md  — формат реєстру
  docs/security.md — запобіжники

