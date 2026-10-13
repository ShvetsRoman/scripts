#!/usr/bin/env bash
# Тести recovery.
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
# shellcheck source=../lib/recovery.sh
source "$ROOT_DIR/lib/recovery.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/backups/recovery"
HOME="$tmp/home"; mkdir -p "$HOME"

setup_confirm() { return 0; }
DRY_RUN=false; SETUP_BACKUP_ENABLED=true

out="$(recovery_list)"
[[ "$out" == *"немає"* ]] || { printf '[FAIL] порожній\n' >&2; exit 1; }

id="2025-01-01_12-00-00_1234"
dir="$ROOT_DIR/backups/recovery/$id"
mkdir -p "$dir/.config/app"
printf "snap\n" > "$dir/.config/app/file"

out="$(recovery_list)"
[[ "$out" == *"$id"* ]] || { printf '[FAIL] list\n' >&2; exit 1; }

mkdir -p "$HOME/.config/app"
printf "current\n" > "$HOME/.config/app/file"
recovery_restore "$id" >/dev/null
[[ "$(cat "$HOME/.config/app/file")" == "snap" ]] || { printf '[FAIL] restore\n' >&2; exit 1; }

recovery_delete "$id" >/dev/null
[[ ! -d "$dir" ]] || { printf '[FAIL] delete\n' >&2; exit 1; }

if recovery_restore "../bad" 2>/dev/null; then printf '[FAIL] traversal\n' >&2; exit 1; fi
if recovery_delete "not-valid" 2>/dev/null; then printf '[FAIL] invalid id\n' >&2; exit 1; fi

printf '[PASS] test-recovery\n'
