#!/usr/bin/env bash
# Тести fs.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$ROOT_DIR/lib/path.sh"
# shellcheck source=../lib/fs.sh
source "$ROOT_DIR/lib/fs.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/a" "$tmp/b"

printf 'same\n' > "$tmp/a/f"
cp -- "$tmp/a/f" "$tmp/b/f"
fs_compare "$tmp/a" "$tmp/b" || { printf '[FAIL] compare однакові\n' >&2; exit 1; }

printf 'diff\n' > "$tmp/b/f"
if fs_compare "$tmp/a" "$tmp/b"; then printf '[FAIL] compare різні\n' >&2; exit 1; fi

DRY_RUN=true
fs_copy "$tmp/a" "$tmp/new" >/dev/null
[[ ! -e "$tmp/new" ]] || { printf '[FAIL] dry-run\n' >&2; exit 1; }
DRY_RUN=false

mkdir -p "$tmp/src" "$tmp/dst"
printf 'x\n' > "$tmp/src/f"
printf 'x\n' > "$tmp/dst/f"
printf 'extra\n' > "$tmp/dst/g"
SYNC_DELETE=true
fs_copy "$tmp/src" "$tmp/dst"
[[ ! -e "$tmp/dst/g" ]] || { printf '[FAIL] --delete\n' >&2; exit 1; }
SYNC_DELETE=false

ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/backups"
printf 'orig\n' > "$tmp/orig"
fs_protect "$tmp/orig" dotfiles "myfile"
found="$(find "$ROOT_DIR/backups/dotfiles" -type f -name myfile -print -quit)"
[[ -n "$found" && "$(cat "$found")" == orig ]] || { printf '[FAIL] protect\n' >&2; exit 1; }

printf '[PASS] test-fs\n'
