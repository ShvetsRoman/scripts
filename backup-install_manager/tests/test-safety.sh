#!/usr/bin/env bash
literal_tilde="$(printf '%s/' '~')"
# Regression suite для P0/P1 помилок v1.0.0.
set -Eeuo pipefail
ORIGINAL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ORIGINAL_ROOT/src/core/ui.sh"
ui_init_colors
source "$ORIGINAL_ROOT/src/core/path.sh"
source "$ORIGINAL_ROOT/src/core/fs.sh"
source "$ORIGINAL_ROOT/src/dotfiles/apply.sh"
source "$ORIGINAL_ROOT/src/dotfiles/sources.sh"
source "$ORIGINAL_ROOT/src/dotfiles/sync.sh"

fail() { printf '[FAIL] test-safety: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$HOME" "$tmp/external" "$tmp/src"
DRY_RUN=false; SETUP_BACKUP_ENABLED=true; SYNC_DELETE=false

# Відмова від синкання через symlink на директорію поза target.
printf 'protected\n' > "$tmp/external/file"
printf 'injected\n' > "$tmp/src/file"
ln -s "$tmp/external" "$tmp/link"
if apply "$tmp/src" "$tmp/link" recovery link >/dev/null 2>&1; then fail 'symlink destination accepted'; fi
[[ "$(cat "$tmp/external/file")" == protected ]] || fail 'external directory modified'

# path_ok_abs має відхиляти /tmp/.. /tmp/. та symlink у будь-якому компоненті.
for x in '/tmp/..' '/tmp/.' "$tmp/link/file"; do
    if path_ok_abs "$x"; then fail "unsafe abs accepted: $x"; fi
done

# --sync-delete без backup не змінює target.
mkdir -p "$tmp/target"
printf 'original\n' > "$tmp/target/file"
printf 'keep\n' > "$tmp/target/extra"
SYNC_DELETE=true; SETUP_BACKUP_ENABLED=false
if apply "$tmp/src" "$tmp/target" recovery target >/dev/null 2>&1; then fail 'delete without backup accepted'; fi
[[ -f "$tmp/target/extra" ]] || fail 'delete without backup deleted extras'
SYNC_DELETE=false; SETUP_BACKUP_ENABLED=true

# Ad-hoc backup-src / restore-src не повинні створювати каталоги у dry-run.
DRY_RUN=true
sync_backup_src "$tmp/src/file" 'nested/dir/config' >/dev/null
[[ ! -e "$ROOT_DIR/dotfiles/nested" ]] || fail 'backup-src dry-run created directory'
mkdir -p "$ROOT_DIR/dotfiles/conf"; printf 'repodata\n' > "$ROOT_DIR/dotfiles/conf/item"
sync_restore_src 'conf/item' "$tmp/new/subdir/" >/dev/null
[[ ! -e "$tmp/new" ]] || fail 'restore-src dry-run created directory'

# Dry-run sources add/remove — тільки читають registry.
printf '[test]\n' > "$ROOT_DIR/config/dotfiles.conf"
printf 'name | home | ~/.zshrc\n' >> "$ROOT_DIR/config/dotfiles.conf"
before="$(sha256sum "$ROOT_DIR/config/dotfiles.conf")"
sources_add extra home "${literal_tilde}.other" test >/dev/null
sources_remove name >/dev/null
[[ "$(sha256sum "$ROOT_DIR/config/dotfiles.conf")" == "$before" ]] || fail 'sources changed in dry-run'
DRY_RUN=false

# CLI source add із 4 параметрами та із legacy 3 параметрами.
sources_add extra home "${literal_tilde}.other" test >/dev/null
sources_add legacy home "${literal_tilde}.legacy" test >/dev/null
sources_load
((${#SRC_ROWS[@]} == 3)) || fail 'sources add new format'

# Відхилення недійсного запису dotfiles.conf у runtime.
printf 'escape | home | ~/../etc\n' >> "$ROOT_DIR/config/dotfiles.conf"
if sources_load 2>/dev/null; then fail 'unsafe registry entry accepted'; fi

# Symlink всередині дерева зберігається без переходу за ціллю.
mkdir -p "$tmp/tree"
ln -s "$tmp/external/file" "$tmp/tree/external"
apply "$tmp/tree" "$tmp/destination" recovery nested >/dev/null 2>&1 || fail 'nested symlink copy failed'
[[ -L "$tmp/destination/external" ]] || fail 'nested symlink not preserved'
[[ "$(cat "$tmp/external/file")" == protected ]] || fail 'external file modified via source symlink'

# Відключений recovery не може бути використаний з --sync-delete.
SYNC_DELETE=true; SETUP_RECOVERY_ENABLED=false
if apply "$tmp/src" "$tmp/target" recovery target >/dev/null 2>&1; then
    fail 'delete without recovery accepted'
fi
SYNC_DELETE=false; SETUP_RECOVERY_ENABLED=true

printf '[PASS] test-safety\n'
