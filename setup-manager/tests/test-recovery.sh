#!/usr/bin/env bash
# Тести реального відновлення за manifest (name ≠ шлях).
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/path.sh"
source "$ROOT_DIR/lib/fs.sh"
source "$ROOT_DIR/lib/apply.sh"
source "$ROOT_DIR/lib/recovery.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/backups/recovery"
HOME="$tmp/home"; mkdir -p "$HOME"
setup_confirm() { return 0; }
DRY_RUN=false; SETUP_BACKUP_ENABLED=true
out="$(recovery_list)"
[[ "$out" == *"немає"* ]] || { printf '[FAIL] порожній список\n' >&2; exit 1; }

printf 'previous\n' > "$HOME/.zshrc"
fs_protect "$HOME/.zshrc" recovery zsh >/dev/null
id="$(find "$ROOT_DIR/backups/recovery" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
[[ -n "$id" ]] || { echo '[FAIL] no snapshot' >&2; exit 1; }
[[ "$(cat "$ROOT_DIR/backups/recovery/$id/manifest.tsv")" == "$(printf 'zsh\t%s' "$HOME/.zshrc")" ]] || {
  echo '[FAIL] wrong manifest target' >&2; exit 1;
}
printf 'changed\n' > "$HOME/.zshrc"
recovery_restore "$id" >/dev/null
[[ "$(cat "$HOME/.zshrc")" == previous ]] || { echo '[FAIL] original not restored' >&2; exit 1; }
[[ ! -e "$HOME/zsh" ]] || { echo '[FAIL] wrong location created' >&2; exit 1; }

# Старий знімок без manifest не можна відновлювати за здогадом.
mkdir -p "$ROOT_DIR/backups/recovery/2025-01-01_12-00-00_1234"
if recovery_restore 2025-01-01_12-00-00_1234 >/dev/null 2>&1; then
    echo '[FAIL] legacy snapshot silently restored' >&2; exit 1
fi
recovery_delete "$id" >/dev/null
[[ ! -d "$ROOT_DIR/backups/recovery/$id" ]] || { echo '[FAIL] delete' >&2; exit 1; }
if recovery_restore '../bad' 2>/dev/null; then echo '[FAIL] traversal' >&2; exit 1; fi
printf '[PASS] test-recovery\n'
