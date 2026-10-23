#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
cp -a "$PROJECT_DIR" "$tmp/repo"
rm -rf -- "$tmp/repo/backups"
mkdir -p -- "$tmp/repo/backups"
export HOME="$tmp/home" SETUP_NO_CLEAR=true
mkdir -p "$HOME" "$tmp/repo/dotfiles/home"
printf 'src-new\n' > "$HOME/.a"
printf 'old\n' > "$tmp/repo/dotfiles/home/.a"
printf '[test]\n' > "$tmp/repo/config/dotfiles.conf"
printf 'a | home | ~/.a\n' >> "$tmp/repo/config/dotfiles.conf"
"$tmp/repo/backup-install_manager.sh" dotfiles backup changed > /dev/null
id="$(find "$tmp/repo/backups/dotfiles" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
[[ -n "$id" ]] || exit 1
"$tmp/repo/backup-install_manager.sh" backups verify dotfiles "$id" > /dev/null
[[ "$("$tmp/repo/backup-install_manager.sh" backups list dotfiles)" == *"$id"* ]] || exit 1
printf 'tamper\n' > "$tmp/repo/backups/dotfiles/$id/data/a"
if "$tmp/repo/backup-install_manager.sh" backups verify dotfiles "$id" > /dev/null 2>&1; then exit 1; fi
printf '[PASS] test-backups-v3\n'
