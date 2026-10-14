#!/usr/bin/env bash
# Regression: глобальний flock, звільнення, тайм-аут, dry-run без запису.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$PROJECT_DIR/lib/path.sh"
# shellcheck source=../lib/lock.sh
source "$PROJECT_DIR/lib/lock.sh"

fail() { printf '[FAIL] test-lock: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR"
SETUP_LOCK_TIMEOUT=0; DRY_RUN=false

# rc == 0: lock залишається лише всередині функції.
setup_with_lock true || fail 'normal lock'
SETUP_LOCK_TIMEOUT=08
setup_with_lock true || fail 'leading zero timeout'
SETUP_LOCK_TIMEOUT=0
[[ -f "$ROOT_DIR/.setup-manager.lock" ]] || fail 'file not created'
[[ -z "${SETUP_LOCK_FD:-}" ]] || fail 'fd leaked'

# rc != 0: функція повертає той самий код і звільняє lock.
rc=0
setup_with_lock false >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail 'exit code not forwarded'
[[ -z "${SETUP_LOCK_FD:-}" ]] || fail 'fd leaked on failure'
setup_with_lock true || fail 'lock not released after failed command'

# Інший процес тримає lock, CLI має отримати 75, не виконуючи дію.
ready="$tmp/ready"
bash -c 'exec 9>>"$1"; flock -n 9 || exit 1; touch "$2"; sleep 10' bash "$ROOT_DIR/.setup-manager.lock" "$ready" &
other=$!
trap 'kill "$other" 2>/dev/null || true; wait "$other" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT
for ((i=0; i<100; i++)); do
    [[ -f "$ready" ]] && break
    sleep .01
done
[[ -f "$ready" ]] || fail 'holder did not start'
# Ненульовий rc від lock важливо зберегти.
rc=0
setup_with_lock touch "$tmp/unwanted" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 75 ]] || fail "expected 75, got $rc"
[[ ! -e "$tmp/unwanted" ]] || fail 'command run under foreign lock'
kill "$other" 2>/dev/null || true
wait "$other" 2>/dev/null || true

# Dry-run не створює lock навіть коли файл відсутній.
rm -f -- "$ROOT_DIR/.setup-manager.lock"
DRY_RUN=true
setup_with_lock true || fail 'dry-run command'
[[ ! -e "$ROOT_DIR/.setup-manager.lock" ]] || fail 'dry-run wrote lock'

# Підміна symlink не дозволена.
DRY_RUN=false
ln -s "$tmp/outside" "$ROOT_DIR/.setup-manager.lock"
rc=0
setup_with_lock touch "$tmp/unwanted" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 ]] || fail 'symlink lock accepted'
[[ ! -e "$tmp/unwanted" ]] || fail 'action under symlink lock'

printf '[PASS] test-lock\n'
