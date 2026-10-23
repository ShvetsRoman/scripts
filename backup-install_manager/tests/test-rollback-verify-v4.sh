#!/usr/bin/env bash
# Перевірка помилки rollback саме ПІСЛЯ невдалої верифікації.
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/dotfiles/apply.sh
source "$repo/src/dotfiles/apply.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf 'new\n' > "$tmp/src"
fs_guard_delete() { return 0; }
path_ok_abs() { return 0; }
path_ok_source() { return 0; }
fs_compare_copy() { return 1; }
fs_copy() { cp -- "$1" "$2"; }
apply_rollback() { return 2; }
log() { printf '[%s] %s\n' "$1" "$2"; }
SETUP_BACKUP_ENABLED=true
DRY_RUN=false
SYNC_DELETE=false
if apply "$tmp/src" "$tmp/dst" dotfiles item >"$tmp/output" 2>&1; then
    printf '[FAIL] apply accepted failed verification\n' >&2
    exit 1
fi
grep -Fq 'автоматичний rollback не вдався' "$tmp/output" || {
    printf '[FAIL] missing explicit rollback error\n' >&2
    cat "$tmp/output" >&2
    exit 1
}
printf '[PASS] test-rollback-verify-v4\n'
