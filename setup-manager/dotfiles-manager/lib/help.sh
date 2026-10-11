#!/usr/bin/env bash

# ============================================================
# HELP
# ============================================================

show_help() {
    cat <<EOF

$SCRIPT_NAME v$VERSION

Використання:
  $SCRIPT_NAME [опції] <команда> [аргументи]

Команди:
  backup                     Backup всього
  backup PATH                Backup конкретного шляху
  backup changed             Backup лише змінених шляхів

  restore                    Відновлення всього
  restore PATH               Відновлення конкретного шляху

  diff                       Показати відмінності між оригіналами і dotfiles
  diff PATH                  Показати відмінності конкретного шляху

  status                     Показати стан оригіналів відносно dotfiles

  verify                     Перевірити повну відповідність оригіналів і dotfiles
  verify PATH                Перевірити відповідність конкретного шляху

  archive create FILE        Створити tar.gz архів поточного dotfiles у dotfiles-archive
  archive list FILE          Показати вміст вибраного tar.gz архіву
  archive restore FILE       Відновити вміст вибраного архіву назад у dotfiles

  recovery list              Показати список резервних копій перед відновленням
  recovery restore NAME      Відновити файли з вибраної резервної копії
  recovery delete NAME       Видалити вибрану резервну копію
  recovery cleanup           Видалити старі резервні копії за лімітом RECOVERY_LIMIT

  clean                      Видалити з dotfiles файли та папки, яких немає у конфігурації
  clean-all                  Повністю видалити весь вміст dotfiles

  config list                Показати конфігурацію

  menu                       Відкрити інтерактивне меню

Опції:
  --dry-run                  Показати дії без внесення змін
  --yes, -y                  Не запитувати підтвердження
  --verbose, -v              Детальний режим
  --help, -h                 Показати допомогу
  --version, -V              Показати версію
  --                         Завершити обробку опцій

Приклади:
  $SCRIPT_NAME backup
  $SCRIPT_NAME backup changed
  $SCRIPT_NAME backup .config/nvim

  $SCRIPT_NAME restore
  $SCRIPT_NAME restore .zshrc

  $SCRIPT_NAME diff
  $SCRIPT_NAME diff .config/nvim

  $SCRIPT_NAME status

  $SCRIPT_NAME verify
  $SCRIPT_NAME verify .zshrc

  $SCRIPT_NAME archive create
  $SCRIPT_NAME archive create my-dotfiles.tar.gz

  $SCRIPT_NAME recovery list

Archive за замовчуванням:
  $ARCHIVE_DIR/${ARCHIVE_PREFIX}_Y-m-d_H-M-S.tar.gz

Основні каталоги:
  Оригінали:   $HOME
  Dotfiles:    $DOTFILES_DIR
  Recovery:    $RECOVERY_DIR
  Archives:    $ARCHIVE_DIR

EOF
}
