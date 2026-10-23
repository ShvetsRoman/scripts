#!/usr/bin/env bash
# Класифікація для status/diff/verify/plan не повинна змінювати файли.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" SETUP_NO_CLEAR=true
mkdir -p "$HOME" "$tmp/repo/dotfiles/home" "$tmp/repo/config"
cp -a -- "$PROJECT_DIR"/. "$tmp/repo/"
rm -rf -- "$tmp/repo/dotfiles"
mkdir -p "$tmp/repo/dotfiles/home"
printf '[test]\n' > "$tmp/repo/config/dotfiles.conf"
printf '%s\n' 'sample | home | ~/.sample' >> "$tmp/repo/config/dotfiles.conf"

status="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles status)"
[[ "$status" == *'[MISSING] sample'* ]] || exit 1
printf 'home\n' > "$HOME/.sample"
status="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles status)"
[[ "$status" == *'[NEW] sample'* ]] || exit 1
plan="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles plan backup)"
[[ "$plan" == *'[COPY] sample'* ]] || exit 1
printf 'repo\n' > "$tmp/repo/dotfiles/home/.sample"
status="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles status)"
[[ "$status" == *'[CHANGED] sample'* ]] || exit 1
printf 'home\n' > "$tmp/repo/dotfiles/home/.sample"
status="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles status)"
[[ "$status" == *'[OK] sample'* ]] || exit 1
rm "$HOME/.sample"
status="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles status)"
[[ "$status" == *'[DEL] sample'* ]] || exit 1
plan="$(bash "$tmp/repo/backup-install_manager.sh" dotfiles plan backup)"
[[ "$plan" == *'[MISSING] sample'* ]] || exit 1
printf '[PASS] test-sync-classify-v4\n'
