#!/usr/bin/env bash
# Тести path.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"

for p in ".zshrc" ".config/nvim" "a/b/c" "a.b-c_d"; do
    path_ok_rel "$p" || { printf '[FAIL] rel: %s\n' "$p" >&2; exit 1; }
done
for p in "" "/etc" "." ".." "../etc" "a/../b" "a/./b"; do
    if path_ok_rel "$p"; then printf '[FAIL] rel прийнято: %s\n' "$p" >&2; exit 1; fi
done

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/a/b"
path_ok_abs "$tmp/a/b" || { printf '[FAIL] abs\n' >&2; exit 1; }
if path_ok_abs "relative"; then printf '[FAIL] rel як abs\n' >&2; exit 1; fi
if path_ok_abs "/a/../b"; then printf '[FAIL] .. прийнято\n' >&2; exit 1; fi
mkdir -p "$tmp/real" "$tmp/dir"
ln -s "$tmp/real" "$tmp/dir/lnk"
if path_ok_abs "$tmp/dir/lnk"; then printf '[FAIL] symlink прийнято\n' >&2; exit 1; fi

printf '[PASS] test-path\n'
