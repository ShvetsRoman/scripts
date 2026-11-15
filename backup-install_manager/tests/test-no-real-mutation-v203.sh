#!/usr/bin/env bash
# Інваріант: read-only виклики CLI з реального проєкту не мутують
# реальні каталоги даних (backups/, archives/, dotfiles/, logs/).
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# Знімок шляхів реального проєкту: відносний шлях, тип, розмір, mtime.
snapshot() {
    {
        find "$PROJECT_DIR/backups" "$PROJECT_DIR/archives" "$PROJECT_DIR/dotfiles" \
            -printf '%P\t%y\t%s\t%T@\n' 2>/dev/null || true
        find "$PROJECT_DIR/logs" -maxdepth 1 -printf 'logs\t%y\t%s\t%T@\n' 2>/dev/null || true
        printf 'lock\t%s\n' "$(stat -c '%y' "$PROJECT_DIR/.setup-manager.lock" 2>/dev/null || true)"
    } | sort > "$tmp/$1"
}

# Лог CLI скеровуємо в temp: інваріант стосується даних, не журналу.
export SETUP_LOG_FILE="$tmp/run.log"
snapshot before
bash "$PROJECT_DIR/backup-install_manager.sh" --version >/dev/null
bash "$PROJECT_DIR/backup-install_manager.sh" sources validate >/dev/null
bash "$PROJECT_DIR/backup-install_manager.sh" dotfiles status >/dev/null
snapshot after

if ! diff -u -- "$tmp/before" "$tmp/after" > "$tmp/diff"; then
    printf '[FAIL] Read-only CLI мутував реальний проєкт:\n' >&2
    cat -- "$tmp/diff" >&2
    exit 1
fi
printf '[PASS] test-no-real-mutation-v203\n'
