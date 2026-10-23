#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
source "$repo/src/core/path.sh"
source "$repo/src/recovery/system_restore.sh"
log() { :; }
setup_confirm() { return 1; }
DRY_RUN=false
SETUP_BACKUP_ENABLED=true
SYNC_DELETE=false
printf 'example\n' > "$tmp/source"
printf 'old\n' > "$tmp/target"
# No arbitrary elevation of abs paths, and no changes to the destination.
if system_restore "$tmp/source" "$tmp/target" test > /dev/null 2>&1; then
    printf '[FAIL] system restore accepted path outside /etc\n' >&2
    exit 1
fi
[[ "$(cat "$tmp/target")" == old ]]
# Symlink sources are rejected even if the target is a system path.
ln -s "$tmp/source" "$tmp/link"
if system_restore "$tmp/link" /etc/samba/smb.conf test > /dev/null 2>&1; then
    printf '[FAIL] system restore accepted source symlink\n' >&2
    exit 1
fi
# The shell must reject --sync-delete before any privileged operations.
SYNC_DELETE=true
if system_restore "$tmp/source" /etc/samba/smb.conf test > /dev/null 2>&1; then
    printf '[FAIL] system restore accepted --sync-delete\n' >&2
    exit 1
fi
printf '[PASS] test-system-restore-v4\n'
