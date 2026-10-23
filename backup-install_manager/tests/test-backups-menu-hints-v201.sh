#!/usr/bin/env bash
# Перевірка пояснень резервних копій без зміни механізмів архівування.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$ROOT_DIR/src/cli/menu.sh"

# Перевіряємо пояснення в усіх трьох рівнях меню.
grep -Fq "'Резервні копії')" "$menu"
grep -Fq "'Архіви')" "$menu"
grep -Fq "'Recovery')" "$menu"
grep -Fq 'Архіви — копії dotfiles/ проєкту, не всього HOME.' "$menu"
grep -Fq 'Символьні та жорсткі посилання в архіві не підтримуються.' "$menu"
grep -Fq 'порожній список — це нормально.' "$menu"

printf '[PASS] test-backups-menu-hints-v201\n'
