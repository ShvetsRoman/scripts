#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
source "$repo/src/recovery/system_restore.sh"
log() { :; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
printf 'replacement\n' > "$tmp/source"
printf 'original\n' > "$tmp/target"
chmod 640 "$tmp/target"
original_owner="$(stat -c %u:%g "$tmp/target")"
_system_restore_copy "$tmp/source" "$tmp/target" "$tmp/backup" || fail 'ordinary copy'
cmp -s "$tmp/source" "$tmp/target" || fail 'content'
[[ "$(stat -c %a "$tmp/target")" == 640 ]] || fail 'file mode'
[[ "$(stat -c %u:%g "$tmp/target")" == "$original_owner" ]] || fail 'owner/group'
[[ "$(cat "$tmp/backup/original")" == original ]] || fail 'backup content'
# Штучна помилка install: файл призначення має залишитися незмінним.
install() {
    if [[ "${1:-}" == -m ]]; then return 1; fi
    command install "$@"
}
printf 'before-failure\n' > "$tmp/target"
if _system_restore_copy "$tmp/source" "$tmp/target" "$tmp/backup-fail"; then
    fail 'failure not propagated'
fi
[[ "$(cat "$tmp/target")" == before-failure ]] || fail 'target changed after install failure'
unset -f install
# Штучна помилка перевірки ПІСЛЯ mv: повинен спрацювати rollback.
cmp() { return 1; }
if _system_restore_copy "$tmp/source" "$tmp/target" "$tmp/backup-rollback"; then
    fail 'verify failure not propagated'
fi
unset -f cmp
[[ "$(cat "$tmp/target")" == before-failure ]] || fail 'rollback did not restore content'
[[ ! -e "$tmp/target.setup-manager" ]] || fail 'unexpected temporary file'
printf '[PASS] test-system-copy-v4\n'
