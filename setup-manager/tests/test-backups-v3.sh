#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
cp -a "$PROJECT_DIR" "$tmp/repo"
export HOME="$tmp/home" SETUP_NO_CLEAR=true
mkdir -p "$HOME" "$tmp/repo/dotfiles"
printf 'src-new\n' > "$HOME/.a"
printf 'old\n' > "$tmp/repo/dotfiles/.a"
printf 'a | home | .a | .a | mygroup\n' > "$tmp/repo/config/sources.conf"
"$tmp/repo/setup.sh" dotfiles backup changed > /dev/null
id="$(find "$tmp/repo/backups/mygroup" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
[[ -n "$id" ]] || exit 1
"$tmp/repo/setup.sh" backups verify mygroup "$id" > /dev/null
[[ "$("$tmp/repo/setup.sh" backups list mygroup)" == "$id" ]] || exit 1
printf 'tamper\n' > "$tmp/repo/backups/mygroup/$id/data/a"
if "$tmp/repo/setup.sh" backups verify mygroup "$id" > /dev/null 2>&1; then exit 1; fi
printf '[PASS] test-backups-v3\n'
