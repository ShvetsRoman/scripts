#!/usr/bin/env bash
# Перевірка ShellCheck для всього проєкту.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v shellcheck >/dev/null 2>&1; then
    printf '[WARN] ShellCheck не встановлений. sudo pacman -S --needed shellcheck\n' >&2
    exit 1
fi
mapfile -d '' -t scripts < <(find "$ROOT" -type f -name '*.sh' -print0)
if (( ${#scripts[@]} == 0 )); then
    printf '[ERROR] Немає Bash-скриптів для перевірки\n' >&2
    exit 1
fi
printf '[INFO] ShellCheck: файлів %d\n' "${#scripts[@]}"
# -x дозволяє аналізувати локальні файли, підключені через source.
# SCRIPTDIR шукає шляхи в директивах # shellcheck source= відносно
# каталогу поточного скрипта, а не поточного робочого каталогу.
shellcheck --external-sources --source-path=SCRIPTDIR --severity=style "${scripts[@]}"
printf '[OK] ShellCheck пройдено\n'
