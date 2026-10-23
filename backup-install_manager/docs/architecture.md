# Архітектура Backup Install Manager

Версія коду — `2.0.2` (читається з `src/core/version.sh`; звіряйте `./backup-install_manager.sh --version`). Remote Sync поки не інтегровано.

```text
backup-install_manager/
├── backup-install_manager.sh         # точка входу
├── config/                  # конфігурації
├── src/
│   ├── core/                # bootstrap, версія, шляхи, UI, блокування
│   ├── cli/                 # CLI та інтерактивні меню
│   ├── packages/            # пакети, конфігурації, реєстр/граф
│   ├── dotfiles/            # джерела, план, порівняння, копіювання
│   ├── recovery/            # backup, recovery, archives
│   ├── hooks/               # запуск hooks у дочірніх процесах
│   └── diagnostics/         # doctor та report
├── hooks/                   # hook_main() для модулів
├── tools/                   # archive_safe.py, recovery_safe.py, update_safe.py
├── tests/                   # регресійні тести
├── docs/                    # документація
├── logs/                    # журнали виконання
└── backups/, archives/, dotfiles/  # користувацькі/runtime-дані
```

Реєстр пакетів містить 13 секцій. `depends` визначає залежності для команд `modules deps/reverse/plan`, але не змінює порядок роботи Packages і hooks. Не видаляйте повторний `source` без аудиту: CLI та hook runtime — різні процеси Bash.

`src/dotfiles/sync.sh:sync_status` не очищає екран; відповідальність за перемальовування несе меню. Логи та runtime-файли не варто включати до релізного пакета.
