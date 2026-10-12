#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/setup.conf
source "$ROOT_DIR/config/setup.conf"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/core.sh
source "$ROOT_DIR/lib/core.sh"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf -- "${TMP_TEST:?}"' EXIT
mkdir -p "$TMP_TEST/a" "$TMP_TEST/b"
printf 'same\n' > "$TMP_TEST/a/file"
cp -- "$TMP_TEST/a/file" "$TMP_TEST/b/file"
touch -t 202001010101 "$TMP_TEST/b/file"
core_compare "$TMP_TEST/a" "$TMP_TEST/b" || { printf '[FAIL] однаковий вміст\n' >&2; exit 1; }
printf 'different\n' > "$TMP_TEST/b/file"
if core_compare "$TMP_TEST/a" "$TMP_TEST/b"; then printf '[FAIL] зміни не знайдені\n' >&2; exit 1; fi
DRY_RUN=true
core_copy "$TMP_TEST/a" "$TMP_TEST/new" >/dev/null
[[ ! -e "$TMP_TEST/new" ]] || { printf '[FAIL] dry-run змінив файли\n' >&2; exit 1; }
DRY_RUN=false
core_copy "$TMP_TEST/a" "$TMP_TEST/new"
core_compare "$TMP_TEST/a" "$TMP_TEST/new" || { printf '[FAIL] копіювання\n' >&2; exit 1; }
if core_safe_relative '../escape'; then printf '[FAIL] path traversal\n' >&2; exit 1; fi
printf '[PASS] Compare, copy, dry-run, path validation\n'
