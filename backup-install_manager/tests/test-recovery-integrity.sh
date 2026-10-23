#!/usr/bin/env bash
# Новий recovery має SHA-256; пошкодження блокують відновлення.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$PROJECT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$PROJECT_DIR/src/core/path.sh"
# shellcheck source=../src/core/fs.sh
source "$PROJECT_DIR/src/core/fs.sh"
# shellcheck source=../src/dotfiles/apply.sh
source "$PROJECT_DIR/src/dotfiles/apply.sh"
# shellcheck source=../src/recovery/recovery.sh
source "$PROJECT_DIR/src/recovery/recovery.sh"
fail() { printf '[FAIL] test-recovery-integrity: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/backups/recovery" "$HOME"
setup_confirm() { return 0; }
SETUP_BACKUP_ENABLED=true
printf 'original\n' > "$HOME/.zshrc"
fs_protect "$HOME/.zshrc" recovery zsh >/dev/null || fail 'snapshot create'
id="$(find "$ROOT_DIR/backups/recovery" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
snap="$ROOT_DIR/backups/recovery/$id"
[[ -f "$snap/checksums.json" ]] || fail 'checksums missing'
recovery_verify "$id" >/dev/null || fail 'verify good snapshot'
printf 'changed\n' > "$HOME/.zshrc"
printf 'corrupted\n' > "$snap/data/zsh"
if recovery_verify "$id" >/dev/null 2>&1; then fail 'corruption not detected'; fi
if recovery_restore "$id" >/dev/null 2>&1; then fail 'tampered recovery restored'; fi
[[ "$(cat "$HOME/.zshrc")" == changed ]] || fail 'target changed after rejected restore'
# Старі 1.1.0 checksums не мають: verify повертає 3, але restore підтримується.
rm -f "$snap/checksums.json"
rc=0
recovery_verify "$id" >/dev/null || rc=$?
[[ "$rc" == 3 ]] || fail "legacy exit status: $rc"
recovery_restore "$id" >/dev/null || fail 'legacy restore'
[[ "$(cat "$HOME/.zshrc")" == corrupted ]] || fail 'legacy restore contents'
# Змінений manifest у перевірюваному новому знімку має відхилятися.
fs_protect "$HOME/.zshrc" recovery zsh >/dev/null || fail 'second snapshot'
newid="$(find "$ROOT_DIR/backups/recovery" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -v -F "$id" | head -1)"
[[ -n "$newid" ]] || fail 'second id'
printf '#comment\n' >> "$ROOT_DIR/backups/recovery/$newid/manifest.tsv"
if recovery_verify "$newid" >/dev/null 2>&1; then fail 'tampered manifest accepted'; fi
printf '[PASS] test-recovery-integrity\n'
