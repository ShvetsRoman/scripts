#!/usr/bin/env bash
# Plan не повинен копіювати, видаляти або створювати каталоги.
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
fail() { printf '[FAIL] test-plan: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$HOME"
printf 'alpha | home | .alpha | .alpha | dotfiles\n' > "$ROOT_DIR/config/sources.conf"
printf 'first\n' > "$HOME/.alpha"
text="$(sync_plan backup)" || fail 'plan backup'
[[ "$text" == *'[COPY]'* && "$text" == *'створити 1'* ]] || fail 'plan classify new'
[[ ! -e "$ROOT_DIR/dotfiles/.alpha" ]] || fail 'plan wrote destination'
if sync_plan invalid >/dev/null 2>&1; then fail 'invalid mode accepted'; fi
if sync_plan backup unknown >/dev/null 2>&1; then fail 'unknown source accepted'; fi
printf 'old\n' > "$ROOT_DIR/dotfiles/.alpha"
text="$(sync_plan backup)" || fail 'plan update'
[[ "$text" == *'[UPDATE]'* && "$text" == *'оновити 1'* ]] || fail 'plan classify update'
[[ "$(cat "$ROOT_DIR/dotfiles/.alpha")" == old ]] || fail 'plan updated target'
text="$(sync_plan restore)" || fail 'plan restore'
[[ "$text" == *'[UPDATE]'* ]] || fail 'restore classification'
printf 'first\n' > "$ROOT_DIR/dotfiles/.alpha"
text="$(sync_plan restore)" || fail 'plan equal'
[[ "$text" == *'[SKIP]'* && "$text" == *'без змін 1'* ]] || fail 'plan equal classification'
rm -f "$HOME/.alpha"
text="$(sync_plan backup)" || fail 'plan missing'
[[ "$text" == *'[MISSING]'* ]] || fail 'plan missing classification'
# Sync-delete: план показує зайві файли, не видаляючи їх.
mkdir -p "$HOME/.dir" "$ROOT_DIR/dotfiles/.dir"
printf 'dir | home | .dir | .dir | dotfiles\n' > "$ROOT_DIR/config/sources.conf"
printf 'a' > "$HOME/.dir/file"
printf 'a' > "$ROOT_DIR/dotfiles/.dir/file"
printf 'extra' > "$ROOT_DIR/dotfiles/.dir/extra"
SYNC_DELETE=true
text="$(sync_plan backup)" || fail 'plan sync-delete'
[[ "$text" == *'[DELETE]'* ]] || fail 'deletion not shown'
[[ -f "$ROOT_DIR/dotfiles/.dir/extra" ]] || fail 'plan deleted file'
printf '[PASS] test-plan\n'
