#!/usr/bin/env bash
# Регресійні тести потоків і необов'язкового журналу UI.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Фіксуємо режим без кольорів для базових перевірок незалежно від TTY.
export NO_COLOR=1
# shellcheck source=../lib/ui.sh
source "$ROOT/lib/ui.sh"

# Тест навмисно створює збій журналу; перевіряємо попередження,
# але не показуємо його користувачеві як реальну помилку.
err_file="$(mktemp)"
trap 'rm -f -- "$err_file"' EXIT
{ result="$(
    _setup_log_sink() { return 1; }
    log_info "повідомлення"
)"; } 2>"$err_file" || {
    printf '[FAIL] Помилка журналу перервала log_info\n' >&2
    exit 1
}
[[ "$result" == '[INFO] повідомлення' ]] || { printf '[FAIL] stdout log_info\n' >&2; exit 1; }
grep -Fq '[WARN] Не вдалося записати повідомлення до журналу Setup Manager.' "$err_file" || { printf '[FAIL] Попередження sink\n' >&2; exit 1; }

# Не намагаємося писати журнал, якщо sink не визначений.
unset -f _setup_log_sink 2>/dev/null || true
[[ "$(log_ok 'готово')" == '[OK] готово' ]] || { printf '[FAIL] stdout log_ok\n' >&2; exit 1; }

# Перенаправлення stdout не впливає на налаштування stderr.
# У нетермінальному тесті обидва потоки мають бути без ANSI.
result="$(NO_COLOR=1 TERM=xterm bash -c 'source "$1/lib/ui.sh"; log_error "помилка"' bash "$ROOT" 2>&1)"
[[ "$result" == '[ERROR] помилка' ]] || { printf '[FAIL] stderr without color\n' >&2; exit 1; }


# Явний колірний режим: stdout та stderr мають ANSI навіть без TTY.
result="$(SETUP_COLOR=always TERM=xterm NO_COLOR='' bash -c 'source "$1/lib/ui.sh"; log_ok "готово"' bash "$ROOT")"
[[ "$result" == *$'\033[0;32m[OK]'* ]] || { printf '[FAIL] stdout ANSI\n' >&2; exit 1; }
result="$(SETUP_COLOR=always TERM=xterm NO_COLOR='' bash -c 'source "$1/lib/ui.sh"; log_error "помилка"' bash "$ROOT" 2>&1)"
[[ "$result" == *$'\033[0;31m[ERROR]'* ]] || { printf '[FAIL] stderr ANSI\n' >&2; exit 1; }

# NO_COLOR і TERM=dumb повинні вимкнути колір навіть із always.
result="$(NO_COLOR=1 SETUP_COLOR=always TERM=xterm bash -c 'source "$1/lib/ui.sh"; log_ok "готово"' bash "$ROOT")"
[[ "$result" == '[OK] готово' ]] || { printf '[FAIL] NO_COLOR or TERM=dumb\n' >&2; exit 1; }
result="$(NO_COLOR='' SETUP_COLOR=always TERM=dumb bash -c 'source "$1/lib/ui.sh"; log_ok "готово"' bash "$ROOT")"
[[ "$result" == '[OK] готово' ]] || { printf '[FAIL] NO_COLOR or TERM=dumb\n' >&2; exit 1; }

printf '[PASS] UI streams, кольори і журнал\n'
