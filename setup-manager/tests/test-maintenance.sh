#!/usr/bin/env bash
# Тести меню, без створення реальних backup та без видалення даних.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(printf '4\n9\n10\n11\n12\n0\n' | bash "$ROOT/setup.sh" maintenance)"
for title in 'АРХІВИ DOTFILES' 'ВИКОРИСТАННЯ ДИСКА' 'MAINTENANCE'; do
    [[ "$out" == *"$title"* ]] || { printf '[FAIL] %s\n' "$title"; exit 1; }
done
help="$(bash "$ROOT/setup.sh" --help)"
[[ "$help" == *'./setup.sh maintenance'* ]]
# Повернення у головне меню без виконання змін.
[[ "$(printf '0\n' | bash "$ROOT/setup.sh" maintenance)" == *'12) Показати використання диска'* ]]
printf '[PASS] Maintenance: меню, архіви, перегляд диска, порожні каталоги\n'
