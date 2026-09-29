#!/usr/bin/env bash

# ============================================================
# HELP
# ============================================================

show_help() {
    cat <<EOF2

$SCRIPT_NAME v$VERSION

Використання:
  $SCRIPT_NAME [опції] <команда> [аргументи]

Команди:
  backup [PATH]             Backup всього або конкретного шляху
  backup changed            Backup лише змінених шляхів
  restore [PATH]            Відновлення всього або конкретного шляху
  diff [PATH]               Показує що саме відрізняється. Тобто виводить конкретні рядки/файли, де є зміни.
  status                    Дає короткий стан кожного шляху: [OK], [NEW], [MISSING], [CHANGED].
  verify [PATH]             Відповідає на питання “backup повністю відповідає HOME чи ні?”
  clean                     Видалити unmanaged top-level entries
  clean-all                 Видалити весь backup
  recovery list             Список recovery snapshots
  recovery restore NAME     Відновити snapshot
  recovery delete NAME      Видалити snapshot
  recovery cleanup          Застосувати retention limit
  archive create [FILE]     Створити tar.gz archive (лише ім’я файлу)
  archive list FILE         Показати archive
  archive restore FILE      Відновити archive у backup
  config list               Показати конфігурацію
  menu                      Інтерактивне меню

aбо:
  $SCRIPT_NAME --version
  $SCRIPT_NAME --help

Опції:
  --dry-run                 Нічого не змінювати
  --yes, -y                 Не питати підтвердження
  --verbose, -v             Детальний режим
  --help, -h                Допомога
  --version, -V             Версія
  --                        Завершити обробку опцій
EOF2
}
