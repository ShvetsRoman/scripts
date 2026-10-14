#!/usr/bin/env bash
# Загальний ранер тестів.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Всі вкладені CLI-процеси успадковують заборону на clear.
export SETUP_TEST_MODE=true
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

# 1. Синтаксис усіх .sh.
while IFS= read -r -d '' f; do
    bash -n "$f" || fail "Синтаксис $f"
done < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
pass 'Синтаксис Bash'

# 2. Версія.
expected="$(bash -c 'source "$1/config/setup.conf"; source "$1/lib/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$ROOT_DIR")"
[[ "$(bash "$ROOT_DIR/setup.sh" --version)" == "$expected" ]] || fail 'Версія'
pass 'Версія'

# 3. Реєстр модулів.
mapfile -t ids < <(bash "$ROOT_DIR/setup.sh" installer --list | awk '{print $1}')
(( ${#ids[@]} >= 1 )) || fail 'Реєстр порожній'
pass "Реєстр: ${#ids[@]} модулів"

# 4. Help містить усі команди. Зберігаємо вивід один раз:
# grep -q у pipe з pipefail може спричинити SIGPIPE (код 141) у producer.
help_output="$(bash "$ROOT_DIR/setup.sh" --help)" || fail 'Help: execution'
[[ "$help_output" == *'sources add'* ]] || fail 'Help: sources add'
[[ "$help_output" == *'archive'* ]] || fail 'Help: archive'
[[ "$help_output" == *'recovery'* ]] || fail 'Help: recovery'
[[ "$help_output" == *'dotfiles plan'* ]] || fail 'Help: dotfiles plan'
[[ "$help_output" == *'recovery list|verify'* ]] || fail 'Help: recovery verify'
[[ "$help_output" == *'dotfiles backup changed'* ]] || fail 'Help: backup changed'
dotfiles_help="$(bash "$ROOT_DIR/setup.sh" dotfiles --help)" || fail 'Help: dotfiles execution'
[[ "$dotfiles_help" == *'dotfiles backup changed'* ]] || fail 'Help: dotfiles --help'
pass 'Help'

# 5. Підтести.
for t in test-path test-fs test-apply test-sources test-sync test-archive test-recovery test-scan test-safety test-lock test-validation test-cli test-plan test-verify test-recovery-integrity test-no-clear test-backup-changed test-rollback-v3 test-recovery-selective test-rotation-v3 test-backups-v3 test-logs-v3 test-status-color test-status-counts; do
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
