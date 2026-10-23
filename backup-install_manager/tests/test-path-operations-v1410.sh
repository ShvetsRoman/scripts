#!/usr/bin/env bash
set -Eeuo pipefail
project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
repo="$tmp/project"; mkdir -p "$repo/config" "$repo/dotfiles" "$tmp/user"
ROOT_DIR="$repo" HOME="$tmp/user"
export ROOT_DIR HOME
source "$project/src/core/ui.sh"
ui_init_colors
source "$project/src/core/path.sh"
source "$project/src/core/fs.sh"
source "$project/src/dotfiles/apply.sh"
source "$project/src/dotfiles/sources.sh"
source "$project/src/dotfiles/sync.sh"
printf '[test]\nalpha | home | ~/.alpha\n' > "$repo/config/dotfiles.conf"
printf 'hello\n' > "$HOME/.alpha"
SETUP_BACKUP_ENABLED=false
DRY_RUN=false
SYNC_DELETE=false
sync_run backup alpha >/dev/null
[[ "$(cat "$repo/dotfiles/home/.alpha")" == hello ]]
printf 'changed\n' > "$repo/dotfiles/home/.alpha"
sync_run restore alpha >/dev/null
[[ "$(cat "$HOME/.alpha")" == changed ]]
# Порожній TYPE: абсолютний шлях зберігається без home/system.
mkdir -p "$tmp/external"
printf 'outside\n' > "$tmp/external/item"
printf '[other]\nexternal | | %s\n' "$tmp/external/item" >> "$repo/config/dotfiles.conf"
sync_run backup external >/dev/null
[[ "$(cat "$repo/dotfiles/${tmp#/}/external/item")" == outside ]]
printf 'returned\n' > "$repo/dotfiles/${tmp#/}/external/item"
sync_run restore external >/dev/null
[[ "$(cat "$tmp/external/item")" == returned ]]
printf '[PASS] test-path-operations-v1410\n' 
