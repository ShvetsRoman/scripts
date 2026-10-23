#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export ROOT_DIR SETUP_LOG_FILE="$tmp/test.log" DRY_RUN=false SYNC_DELETE=false SETUP_BACKUP_ENABLED=true
# Підключаємо UI перед файловим ядром: fs_protect використовує recovery_helper_run.
# shellcheck source=../src/core/ui.sh
source "$ROOT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/core/fs.sh
source "$ROOT_DIR/src/core/fs.sh"
log() { :; }
mkdir -p "$tmp/src/conf.d" "$tmp/dst" "$tmp/outside"
printf 'safe\n' > "$tmp/src/config"
printf 'protected\n' > "$tmp/outside/file"
ln -s config "$tmp/src/local.conf"
ln -s "$tmp/outside/file" "$tmp/src/conf.d/external.conf"
fs_copy "$tmp/src" "$tmp/dst/cfg"
[[ -L "$tmp/dst/cfg/local.conf" && "$(readlink "$tmp/dst/cfg/local.conf")" == config ]]
[[ -L "$tmp/dst/cfg/conf.d/external.conf" ]]
[[ "$(cat "$tmp/outside/file")" == protected ]]
fs_compare "$tmp/src" "$tmp/dst/cfg"
# The destination must not follow a symlink in any ancestor component.
ln -s "$tmp/outside" "$tmp/redirect"
if fs_copy "$tmp/src/config" "$tmp/redirect/unsafe"; then
    printf '[FAIL] symlink destination path accepted\n' >&2; exit 1
fi
[[ ! -e "$tmp/outside/unsafe" ]]
# Do not follow symlinks in source ancestors either.
if fs_copy "$tmp/redirect/file" "$tmp/dst/unsafe"; then
    printf '[FAIL] symlink source ancestor accepted\n' >&2; exit 1
fi
# Running twice must not destroy or dereference preserved links.
fs_copy "$tmp/src" "$tmp/dst/cfg"
fs_compare "$tmp/src" "$tmp/dst/cfg"
# Snapshot integrity must record symlinks without following their targets.
log() { printf '[%s] %s\n' "$1" "${*:2}" > /dev/null; }
mkdir -p "$ROOT_DIR/backups"
fs_protect "$tmp/src" dotfiles symlink-test
[[ -n "${FS_PROTECT_SNAPSHOT:-}" ]]
python3 "$ROOT_DIR/tools/recovery_safe.py" verify "$FS_PROTECT_SNAPSHOT" >/dev/null
python3 - "$FS_PROTECT_SNAPSHOT/checksums.json" <<'PYTEST'
import json, sys
entries = json.load(open(sys.argv[1], encoding='utf-8'))['entries']
assert any(e['type'] == 'symlink' and e['path'].endswith('external.conf') for e in entries)
PYTEST
printf '[PASS] test-symlinks-v4\n'
