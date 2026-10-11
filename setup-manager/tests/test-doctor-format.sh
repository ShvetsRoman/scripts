#!/usr/bin/env bash
# Перевірка виводу Doctor без зміни системи.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output_file="$(mktemp)"
trap 'rm -f -- "$output_file"' EXIT
NO_COLOR=1 bash "$ROOT/setup.sh" doctor >"$output_file" 2>&1 || true
output="$(cat "$output_file")"
[[ "$output" == *$'[OK] Синтаксис точок входу\n\nПідсумок:'* ]] || {
    printf '[FAIL] Немає порожнього рядка перед підсумком Doctor\n' >&2
    exit 1
}
tail -n 2 "$output_file" | head -n 1 | grep -Eq '^Підсумок: модулів [0-9]+, помилок [0-9]+, попереджень [0-9]+$' || {
    printf '[FAIL] Немає порожнього рядка після підсумку Doctor\n' >&2
    exit 1
}
[[ "$output" != *$'\033['* ]] || {
    printf '[FAIL] ANSI-коди у режимі NO_COLOR\n' >&2
    exit 1
}
grep -Fq 'Синхронізувати змінені конфіги з Dotfiles Manager?' "$ROOT/setup.sh"
grep -Fq "run_dotfiles backup changed" "$ROOT/setup.sh"
printf '[PASS] Формат Doctor і пояснення backup Dotfiles\n'
# Повідомлення Smart Setup повинні проходити через спільний кольоровий logger.
grep -Fq "log_info 'Додатковий backup синхронізує" "$ROOT/setup.sh"
grep -Fq "log_info 'У сховищі можуть бути замінені" "$ROOT/setup.sh"
python - "$ROOT/setup.sh" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
assert "log_info 'У сховищі можуть бути замінені попередні версії; це не захисний архів.'\n        printf '\\n'\n        if ask_yes" in s
PY
printf '[PASS] Кольоровий log_info і відступ перед запитанням\n'
