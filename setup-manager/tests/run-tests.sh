#!/usr/bin/env bash
# Загальний ранер тестів.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

# 1. Синтаксис усіх .sh.
while IFS= read -r -d '' f; do
    bash -n "$f" || fail "Синтаксис $f"
done < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
pass 'Синтаксис Bash'

# 2. Версія.
expected="$(bash -c 'source "$1/config/setup.conf"; printf "%s" "$SETUP_VERSION"' bash "$ROOT_DIR")"
[[ "$(bash "$ROOT_DIR/setup.sh" --version)" == "$expected" ]] || fail 'Версія'
pass 'Версія'

# 3. Реєстр модулів.
mapfile -t ids < <(bash "$ROOT_DIR/setup.sh" installer --list | awk '{print $1}')
(( ${#ids[@]} >= 1 )) || fail 'Реєстр порожній'
pass "Реєстр: ${#ids[@]} модулів"

# 4. Help містить усі команди.
bash "$ROOT_DIR/setup.sh" --help | grep -q 'sources seed' || fail 'Help: sources seed'
bash "$ROOT_DIR/setup.sh" --help | grep -q 'archive' || fail 'Help: archive'
bash "$ROOT_DIR/setup.sh" --help | grep -q 'recovery' || fail 'Help: recovery'
pass 'Help'

# 5. Підтести.
for t in test-path test-fs test-apply test-sources test-sync test-archive test-recovery test-seed; do
    f="$ROOT_DIR/tests/$t.sh"
    [[ -f "$f" ]] && bash "$f" || fail "$t"
done
pass 'Підтести'

# 6. ShellCheck.
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' -t files < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
    shellcheck -x --source-path=SCRIPTDIR -S warning "${files[@]}" || fail 'ShellCheck'
    pass 'ShellCheck'
else
    printf '[SKIP] ShellCheck\n'
fi

printf '\n[PASS] Усі перевірки пройдено\n'
