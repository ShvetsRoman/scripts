#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/src/core/path.sh"
source "$repo/src/core/fs.sh"
source "$repo/src/dotfiles/apply.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"
mkdir -p "$ROOT_DIR" "$tmp/src" "$tmp/dst" "$tmp/external"
log() { :; }
printf 'original\n' > "$tmp/external/valuable"
printf 'replacement\n' > "$tmp/src/new"
ln -s "$tmp/external/valuable" "$tmp/src/linked"
ln -s "$tmp/external" "$tmp/dst/linked-dir"
printf 'outdated\n' > "$tmp/dst/old"
DRY_RUN=false
SETUP_BACKUP_ENABLED=true
SYNC_DELETE=true
# --sync-delete may remove extra entries but must never traverse links.
fs_copy "$tmp/src" "$tmp/dst"
[[ ! -e "$tmp/dst/old" ]]
[[ -L "$tmp/dst/linked" ]]
[[ ! -e "$tmp/dst/linked-dir" ]]
[[ "$(cat "$tmp/external/valuable")" == original ]]
fs_compare "$tmp/src" "$tmp/dst"
# Rejection of unsafe destination ancestors must not affect external files.
ln -s "$tmp/external" "$tmp/escape"
if fs_copy "$tmp/src/new" "$tmp/escape/valuable"; then
    echo '[FAIL] symlink ancestor accepted' >&2
    exit 1
fi
[[ "$(cat "$tmp/external/valuable")" == original ]]
# No backup plus --sync-delete must be rejected without modification.
SETUP_BACKUP_ENABLED=false
printf 'keep\n' > "$tmp/dst/keep"
if fs_copy "$tmp/src" "$tmp/dst"; then
    echo '[FAIL] deletion without backup accepted' >&2
    exit 1
fi
[[ -f "$tmp/dst/keep" ]]
SETUP_BACKUP_ENABLED=true
SYNC_DELETE=false
# Simulate failed copy AND failed rollback: failure must be logged.
printf 'old value\n' > "$tmp/dst/file"
printf 'new value\n' > "$tmp/source-file"
fs_copy() { return 1; }
fs_protect() { FS_PROTECT_SNAPSHOT="simulated"; return 0; }
apply_rollback() { return 2; }
errors="$tmp/errors.log"
log() { if [[ "$1" == error ]]; then printf '%s\n' "$2" >> "$errors"; fi; }
if apply "$tmp/source-file" "$tmp/dst/file" dotfiles item; then
    echo '[FAIL] apply reported success on failed copy' >&2
    exit 1
fi
grep -q 'rollback не вдався' "$errors"
printf '[PASS] test-transaction-safety-v4\n'
