#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$PROJECT_DIR/lib/path.sh"
# shellcheck source=../lib/fs.sh
source "$PROJECT_DIR/lib/fs.sh"
# shellcheck source=../lib/sources.sh
source "$PROJECT_DIR/lib/sources.sh"
# shellcheck source=../lib/sync.sh
source "$PROJECT_DIR/lib/sync.sh"
fail() { printf '[FAIL] test-verify: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$HOME"
printf 'alpha | home | .alpha | .alpha | dotfiles\n' > "$ROOT_DIR/config/sources.conf"
printf 'first\n' > "$HOME/.alpha"
sync_verify alpha >/dev/null || fail 'missing повернув помилковий код'
printf 'first\n' > "$ROOT_DIR/dotfiles/.alpha"
text="$(sync_verify alpha)" || fail 'matching files rejected'
[[ "$text" == *'однакових 1'* ]] || fail 'verify summary'
printf 'different\n' > "$ROOT_DIR/dotfiles/.alpha"
sync_verify alpha >/dev/null || fail 'drift повернув помилковий код'
[[ "$(cat "$HOME/.alpha")" == first ]] || fail 'verify wrote source'
if sync_verify nonexistent >/dev/null 2>&1; then fail 'unknown filter accepted'; fi
printf '[PASS] test-verify\n'
