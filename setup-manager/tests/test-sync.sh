#!/usr/bin/env bash
# Тести sync.
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
# shellcheck source=../lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=../lib/sync.sh
source "$ROOT_DIR/lib/sync.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$ROOT_DIR/backups"
HOME="$tmp/home"; mkdir -p "$HOME"

setup_confirm() { return 0; }
DRY_RUN=false; SETUP_BACKUP_ENABLED=true

cat > "$ROOT_DIR/config/sources.conf" <<'CONF'
home | .zshrc | .zshrc | dotfiles
CONF
printf 'content\n' > "$HOME/.zshrc"

sync_run backup >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/.zshrc")" == content ]] || { printf '[FAIL] backup\n' >&2; exit 1; }

sync_run backup >/dev/null
(( $? == 0 )) || { printf '[FAIL] idempotent\n' >&2; exit 1; }

printf 'new\n' > "$HOME/.zshrc"
sync_run backup >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/.zshrc")" == new ]] || { printf '[FAIL] update\n' >&2; exit 1; }
old="$(find "$ROOT_DIR/backups/dotfiles" -type f -name .zshrc -print -quit)"
[[ -n "$old" && "$(cat "$old")" == content ]] || { printf '[FAIL] backup old\n' >&2; exit 1; }

printf 'local\n' > "$HOME/.zshrc"
sync_run restore >/dev/null
[[ "$(cat "$HOME/.zshrc")" == new ]] || { printf '[FAIL] restore\n' >&2; exit 1; }

sync_run backup >/dev/null
sync_status >/dev/null || { printf '[FAIL] status\n' >&2; exit 1; }

printf 'changed\n' > "$HOME/.zshrc"
if sync_diff >/dev/null 2>&1; then printf '[FAIL] diff\n' >&2; exit 1; fi

printf '[PASS] test-sync\n'
