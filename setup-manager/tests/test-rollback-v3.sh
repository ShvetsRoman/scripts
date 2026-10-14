#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$PROJECT_DIR/lib/path.sh"
# shellcheck source=../lib/fs.sh
source "$PROJECT_DIR/lib/fs.sh"
# shellcheck source=../lib/apply.sh
source "$PROJECT_DIR/lib/apply.sh"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/backups" "$tmp/data"
SETUP_BACKUP_ENABLED=true
DRY_RUN=false
printf 'new\n' > "$tmp/src"
printf 'old\n' > "$tmp/dest"
# Націлено зламати fs_copy тільки для головного запису, не для fs_protect/rollback.
eval "$(declare -f fs_copy | sed '1s/^fs_copy ()/fs_copy_real ()/')"
fs_copy() {
    if [[ "$1" == "$tmp/src" ]]; then
        printf 'PARTIAL\n' > "$2"
        return 1
    fi
    fs_copy_real "$@"
}
if apply "$tmp/src" "$tmp/dest" dotfiles item >/dev/null 2>&1; then
    printf '[FAIL] test-rollback-v3: no error\n' >&2; exit 1
fi
[[ "$(cat "$tmp/dest")" == old ]] || { printf '[FAIL] rollback missing\n' >&2; exit 1; }
# Якщо ціль нова, при помилці прибираємо частково створений файл.
if apply "$tmp/src" "$tmp/created" dotfiles newitem >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$tmp/created" ]] || exit 1
id="$(find "$ROOT_DIR/backups/dotfiles" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
[[ -f "$ROOT_DIR/backups/dotfiles/$id/checksums.json" ]] || exit 1
python3 "$PROJECT_DIR/tools/recovery_safe.py" verify "$ROOT_DIR/backups/dotfiles/$id" >/dev/null || exit 1
printf '[PASS] test-rollback-v3\n'
