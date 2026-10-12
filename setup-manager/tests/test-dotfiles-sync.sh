#!/usr/bin/env bash
set -Eeuo pipefail
project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/repo/config" "$tmp/repo/dotfiles/.config/app" "$tmp/home/.config/app"
printf 'BACKUP_FILES=(".zshrc")\nBACKUP_DIRS=(".config/app")\n' > "$tmp/repo/config/dotfiles.conf"
printf 'old\n' > "$tmp/repo/dotfiles/.zshrc"
printf 'new\n' > "$tmp/home/.zshrc"
printf 'v1\n' > "$tmp/repo/dotfiles/.config/app/settings"
printf 'v2\n' > "$tmp/home/.config/app/settings"
printf 'extra\n' > "$tmp/repo/dotfiles/.config/app/extra"
# Ізольований запуск тих самих функцій, що викликає setup.sh.
bash -c '
    set -Eeuo pipefail
    source "$1/lib/ui.sh"
    source "$1/lib/core.sh"
    source "$1/lib/dotfiles.sh"
    ROOT_DIR="$2"
    HOME="$3"
    SETUP_BACKUP_ENABLED=true
    SETUP_RECOVERY_ENABLED=true
    DRY_RUN=true
    output="$(dotfiles_sync backup .zshrc)"
    [[ "$output" == *"[DRY-RUN] backup: заплановано 1"* ]]
    [[ "$(cat "$ROOT_DIR/dotfiles/.zshrc")" == old ]]
    [[ ! -d "$ROOT_DIR/backups/dotfiles" ]]
    DRY_RUN=false
    dotfiles_sync backup .zshrc >/dev/null
    [[ "$(cat "$ROOT_DIR/dotfiles/.zshrc")" == new ]]
    previous="$(find "$ROOT_DIR/backups/dotfiles" -type f -name .zshrc -print -quit)"
    [[ -n "$previous" && "$(cat "$previous")" == old ]]
    before="$(find "$ROOT_DIR/backups/dotfiles" -type f | wc -l)"
    dotfiles_sync backup .zshrc >/dev/null
    after="$(find "$ROOT_DIR/backups/dotfiles" -type f | wc -l)"
    [[ "$before" == "$after" ]]
    # Restore: перевірка recovery перед перезаписом.
    printf "local\\n" > "$HOME/.zshrc"
    dotfiles_sync restore .zshrc >/dev/null
    [[ "$(cat "$HOME/.zshrc")" == new ]]
    previous="$(find "$ROOT_DIR/backups/recovery" -type f -name .zshrc -print -quit)"
    [[ -n "$previous" && "$(cat "$previous")" == local ]]
    # Додатковий файл у призначенні не видаляється.
    dotfiles_sync backup .config/app >/dev/null
    [[ "$(cat "$ROOT_DIR/dotfiles/.config/app/settings")" == v2 ]]
    [[ -e "$ROOT_DIR/dotfiles/.config/app/extra" ]]
    # Diff показує тільки змінені шляхи, не однакові.
    output="$(dotfiles_diff .zshrc)"
    [[ -z "$output" ]]
    printf "different\\n" > "$HOME/.zshrc"
    if output="$(dotfiles_diff .zshrc)"; then
        exit 1
    fi
    [[ "$output" == *"Diff: .zshrc"* ]]
' bash "$project" "$tmp/repo" "$tmp/home"
printf '[PASS] Dotfiles Sync: dry-run, backup, restore, recovery, skip, extras, diff\n'
