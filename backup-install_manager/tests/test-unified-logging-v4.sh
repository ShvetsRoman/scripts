#!/usr/bin/env bash
# Регресійна перевірка спільного логування Recovery та окремих hooks.
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export SETUP_LOG_FILE="$tmp/setup.log"
export SETUP_RUN_ID='logging-test'
export SETUP_COLOR=never
export SETUP_TEST_MODE=true
ROOT_DIR="$repo"
DRY_RUN=false
# shellcheck source=../src/core/ui.sh
source "$repo/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/hooks/hooks.sh
source "$repo/src/core/path.sh"
source "$repo/src/hooks/hooks.sh"

# Python-помічник: два статуси без дублювання префіксів.
cat > "$tmp/recovery-ok.py" <<'PY'
print('[OK] Recovery integrity: 1 об’єктів')
print('[WARN] Recovery: тестове попередження')
PY
out="$(recovery_helper_run "$tmp/recovery-ok.py")"
[[ "$out" == *"[OK] Recovery integrity: 1 об’єктів"* ]]
[[ "$out" == *'[WARN] Recovery: тестове попередження'* ]]
[[ "$out" != *'[OK] [OK]'* ]]
grep -Fq "[OK] Recovery integrity: 1 об’єктів" "$SETUP_LOG_FILE"
grep -Fq '[WARN] Recovery: тестове попередження' "$SETUP_LOG_FILE"

# Код виходу 3 має залишатися 3, а stderr має перейти у спільний лог.
cat > "$tmp/recovery-error.py" <<'PY'
import sys
print('[ERROR] Recovery: контрольована помилка', file=sys.stderr)
sys.exit(3)
PY
rc=0
recovery_helper_run "$tmp/recovery-error.py" > "$tmp/recovery.out" 2> "$tmp/recovery.err" || rc=$?
[[ "$rc" -eq 3 ]]
grep -Fq '[ERROR] Recovery: контрольована помилка' "$tmp/recovery.err"
grep -Fq '[ERROR] Recovery: контрольована помилка' "$SETUP_LOG_FILE"

# Hook запускається в окремому Bash-процесі та використовує той самий журнал.
mkdir -p "$tmp/project/hooks" "$tmp/project/src/core" "$tmp/project/src/hooks"
cp "$repo/src/core/"{path,ui}.sh "$tmp/project/src/core/"
cp "$repo/src/hooks/hook_runtime.sh" "$tmp/project/src/hooks/"
cat > "$tmp/project/hooks/example.sh" <<'HOOK'
#!/usr/bin/env bash
hook_main() {
    log info 'Тестове повідомлення hook'
}
HOOK
ROOT_DIR="$tmp/project"
declare -A PACKAGE_HOOKS=([demo]=example)
out="$(hooks_run demo)"
[[ "$out" == *'[INFO] Тестове повідомлення hook'* ]]
[[ "$out" == *'[OK] Загальний hook example виконано'* ]]
grep -Fq '[INFO] Тестове повідомлення hook' "$SETUP_LOG_FILE"
grep -Fq '[OK] Загальний hook example виконано' "$SETUP_LOG_FILE"

# --dry-run не запускає hook і не додає його повідомлення до журналу.
DRY_RUN=true
before="$(grep -Fc '[INFO] Тестове повідомлення hook' "$SETUP_LOG_FILE")"
hooks_run demo >/dev/null
after="$(grep -Fc '[INFO] Тестове повідомлення hook' "$SETUP_LOG_FILE")"
[[ "$before" -eq "$after" ]]

printf '[PASS] test-unified-logging-v4\n'
