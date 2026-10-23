#!/usr/bin/env bash
# Запуск ShellCheck з налаштуваннями проєкту (.shellcheckrc).
#
#   tests/lint.sh         продакшн-код (backup-sync.sh + усі lib/*.sh через source-директиви), рівень >= warning.
#                         Код виходу 1, якщо є зауваження. Тести (tests/*.sh) перевіряються інформаційно.
#   tests/lint.sh --all   усі файли і всі рівні (info/style) — для перегляду; код виходу завжди 0.
#
# Формат виводу gcc (`файл:рядок:колонка: рівень: опис [SCxxxx]`) — компактний, зручно копіювати.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
    printf '[ERROR] ShellCheck не встановлений. Встановіть: apt install shellcheck | brew install shellcheck | https://www.shellcheck.net\n' >&2
    exit 127
fi

shellcheck --version | sed -n '1,2p;/^version/p' | head -n 2

if [[ "${1:-}" == "--all" ]]; then
    printf '\n== ShellCheck: усі файли, усі рівні ==\n'
    shellcheck -x -S style -f gcc backup-sync.sh tests/*.sh || true
    exit 0
fi

prod_rc=0
printf '\n== ShellCheck: backup-sync.sh + lib/ (рівень >= warning) ==\n'
shellcheck -x -S warning -f gcc backup-sync.sh || prod_rc=$?

printf '\n== ShellCheck: tests/ (інформаційно, рівень >= warning) ==\n'
if ! shellcheck -x -S warning -f gcc tests/*.sh; then
    printf '[WARN] Зауваження в tests/ не вважаються помилкою прогону.\n'
fi

if ((prod_rc != 0)); then
    printf '[FAIL] Є зауваження ShellCheck у продакшн-коді.\n' >&2
    exit 1
fi
printf '[PASS] Продакшн-код: зауважень рівня warning і вище немає.\n'
