#!/usr/bin/env bash
# Тести sync.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$ROOT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/core/fs.sh
source "$ROOT_DIR/src/core/fs.sh"
# shellcheck source=../src/dotfiles/apply.sh
source "$ROOT_DIR/src/dotfiles/apply.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/dotfiles/sync.sh
source "$ROOT_DIR/src/dotfiles/sync.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$ROOT_DIR/backups"
HOME="$tmp/home"; mkdir -p "$HOME"

setup_confirm() { return 0; }
DRY_RUN=false; SETUP_BACKUP_ENABLED=true

cat > "$ROOT_DIR/config/dotfiles.conf" <<'CONF'
[test]
zsh | home | ~/.zshrc
CONF
printf 'content\n' > "$HOME/.zshrc"

sync_run backup >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/home/.zshrc")" == content ]] || { printf '[FAIL] backup\n' >&2; exit 1; }

sync_run backup >/dev/null
(( $? == 0 )) || { printf '[FAIL] idempotent\n' >&2; exit 1; }

printf 'new\n' > "$HOME/.zshrc"
sync_run backup >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/home/.zshrc")" == new ]] || { printf '[FAIL] update\n' >&2; exit 1; }
old="$(find "$ROOT_DIR/backups/dotfiles" -type f -name zsh -print -quit)"
[[ -n "$old" && "$(cat "$old")" == content ]] || { printf '[FAIL] backup old\n' >&2; exit 1; }

printf 'local\n' > "$HOME/.zshrc"
sync_run restore >/dev/null
[[ "$(cat "$HOME/.zshrc")" == new ]] || { printf '[FAIL] restore\n' >&2; exit 1; }

sync_run backup >/dev/null
sync_status >/dev/null || { printf '[FAIL] status\n' >&2; exit 1; }

printf 'changed\n' > "$HOME/.zshrc"
sync_diff >/dev/null || { printf '[FAIL] diff повернув помилку для звичайних змін\n' >&2; exit 1; }

printf '[PASS] test-sync\n'
