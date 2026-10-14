#!/usr/bin/env bash
# Тести apply.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$ROOT_DIR/lib/path.sh"
# shellcheck source=../lib/fs.sh
source "$ROOT_DIR/lib/fs.sh"
# shellcheck source=../lib/apply.sh
source "$ROOT_DIR/lib/apply.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/backups"
DRY_RUN=false; SETUP_BACKUP_ENABLED=true

apply "$tmp/missing" "$tmp/dst" dotfiles "missing" >/dev/null
(( $? == 0 )) || { printf '[FAIL] missing\n' >&2; exit 1; }

printf 'hello\n' > "$tmp/src"
apply "$tmp/src" "$tmp/dst" dotfiles "test" >/dev/null
[[ "$APPLY_RESULT" == changed ]] || { printf '[FAIL] changed state\n' >&2; exit 1; }
[[ "$(cat "$tmp/dst")" == hello ]] || { printf '[FAIL] content\n' >&2; exit 1; }

apply "$tmp/src" "$tmp/dst" dotfiles "test" >/dev/null
[[ "$APPLY_RESULT" == unchanged ]] || { printf '[FAIL] idempotent\n' >&2; exit 1; }

printf 'world\n' > "$tmp/src"
apply "$tmp/src" "$tmp/dst" dotfiles "test" >/dev/null
old="$(find "$ROOT_DIR/backups/dotfiles" -type f -name test -print -quit)"
[[ -n "$old" && "$(cat "$old")" == hello ]] || { printf '[FAIL] backup\n' >&2; exit 1; }

printf '[PASS] test-apply\n'
