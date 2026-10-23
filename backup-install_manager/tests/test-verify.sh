#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$PROJECT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$PROJECT_DIR/src/core/path.sh"
# shellcheck source=../src/core/fs.sh
source "$PROJECT_DIR/src/core/fs.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$PROJECT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/dotfiles/sync.sh
source "$PROJECT_DIR/src/dotfiles/sync.sh"
fail() { printf '[FAIL] test-verify: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles/home" "$HOME"
printf '[test]\n' > "$ROOT_DIR/config/dotfiles.conf"
printf 'alpha | home | ~/.alpha\n' >> "$ROOT_DIR/config/dotfiles.conf"
printf 'first\n' > "$HOME/.alpha"
sync_verify alpha >/dev/null || fail 'missing повернув помилковий код'
printf 'first\n' > "$ROOT_DIR/dotfiles/home/.alpha"
text="$(sync_verify alpha)" || fail 'matching files rejected'
[[ "$text" == *'однакових 1'* ]] || fail 'verify summary'
printf 'different\n' > "$ROOT_DIR/dotfiles/home/.alpha"
sync_verify alpha >/dev/null || fail 'drift повернув помилковий код'
[[ "$(cat "$HOME/.alpha")" == first ]] || fail 'verify wrote source'
if sync_verify nonexistent >/dev/null 2>&1; then fail 'unknown filter accepted'; fi
printf '[PASS] test-verify\n'
