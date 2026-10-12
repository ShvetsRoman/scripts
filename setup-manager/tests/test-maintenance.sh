#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'command rm -rf -- "$TMP"' EXIT
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/maintenance.sh
source "$PROJECT_DIR/lib/maintenance.sh"
ROOT_DIR="$TMP/project"
SETUP_KEEP_DAYS=30
DRY_RUN=false
CONFIRM_CALLS=0
setup_confirm() { ((CONFIRM_CALLS+=1)); return 0; }
for category in installer dotfiles recovery; do
    mkdir -p -- "$ROOT_DIR/backups/$category/old" "$ROOT_DIR/backups/$category/new"
    printf 'old\n' > "$ROOT_DIR/backups/$category/old/config"
    printf 'new\n' > "$ROOT_DIR/backups/$category/new/config"
    touch -d '31 days ago' -- "$ROOT_DIR/backups/$category/old"
done
mkdir -p -- "$ROOT_DIR/logs"
printf 'old\n' > "$ROOT_DIR/logs/old.log"
printf 'new\n' > "$ROOT_DIR/logs/new.log"
touch -d '31 days ago' -- "$ROOT_DIR/logs/old.log"

DRY_RUN=true
for category in installer dotfiles recovery logs; do
    maintenance_cleanup "$category" >/dev/null
    if [[ "$category" == logs ]]; then
        [[ -f "$ROOT_DIR/logs/old.log" ]] || exit 1
    else
        [[ -d "$ROOT_DIR/backups/$category/old" ]] || exit 1
    fi
done
[[ "$CONFIRM_CALLS" == 0 ]] || { echo '[FAIL] dry-run викликав підтвердження'; exit 1; }
echo '[PASS] Maintenance dry-run без змін і підтвердження'

DRY_RUN=false
for category in installer dotfiles recovery logs; do
    maintenance_cleanup "$category" >/dev/null
    if [[ "$category" == logs ]]; then
        [[ ! -e "$ROOT_DIR/logs/old.log" && -f "$ROOT_DIR/logs/new.log" ]] || exit 1
    else
        [[ ! -e "$ROOT_DIR/backups/$category/old" && -f "$ROOT_DIR/backups/$category/new/config" ]] || exit 1
    fi
done
[[ "$CONFIRM_CALLS" == 4 ]] || exit 1
echo '[PASS] Maintenance 4 категорії: старі видалено, нові збережено'

# 30 діб + 2 хвилини — очищення; 29 діб — без змін.
mkdir -p -- "$ROOT_DIR/backups/dotfiles/boundary" "$ROOT_DIR/backups/dotfiles/recent"
touch -d '30 days ago 2 minutes ago' -- "$ROOT_DIR/backups/dotfiles/boundary"
touch -d '29 days ago' -- "$ROOT_DIR/backups/dotfiles/recent"
maintenance_cleanup dotfiles >/dev/null
[[ ! -e "$ROOT_DIR/backups/dotfiles/boundary" && -d "$ROOT_DIR/backups/dotfiles/recent" ]] || exit 1
echo '[PASS] Maintenance межа 30 повних діб'

# Символьні посилання в цільовій категорії й її батьківському каталозі відхиляються.
mkdir -p -- "$TMP/outside" "$ROOT_DIR/alternative"
printf 'keep\n' > "$TMP/outside/sentinel"
mv -- "$ROOT_DIR/backups/dotfiles" "$ROOT_DIR/alternative/dotfiles"
ln -s -- "$TMP/outside" "$ROOT_DIR/backups/dotfiles"
if maintenance_cleanup dotfiles >/dev/null 2>&1; then
    echo '[FAIL] Maintenance прийняв symlink'; exit 1
fi
[[ -f "$TMP/outside/sentinel" ]] || exit 1
command rm -- "$ROOT_DIR/backups/dotfiles"
mv -- "$ROOT_DIR/alternative/dotfiles" "$ROOT_DIR/backups/dotfiles"
if maintenance_cleanup invalid >/dev/null 2>&1; then exit 1; fi
SETUP_KEEP_DAYS=0
if maintenance_cleanup logs >/dev/null 2>&1; then exit 1; fi
echo '[PASS] Maintenance валідація шляхів, типу і терміну'

# CLI працює без підтвердження у режимі dry-run.
SETUP_KEEP_DAYS=30
DRY_RUN=false
mkdir -p -- "$ROOT_DIR/backups/dotfiles/cli-old"
touch -d '40 days ago' -- "$ROOT_DIR/backups/dotfiles/cli-old"
maintenance_main --dry-run cleanup dotfiles >/dev/null
[[ -d "$ROOT_DIR/backups/dotfiles/cli-old" ]] || exit 1
echo '[PASS] Maintenance CLI --dry-run'
