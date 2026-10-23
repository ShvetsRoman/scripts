#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
cp -a -- "$PROJECT_DIR" "$tmp/repo"
export HOME="$tmp/home" SETUP_NO_CLEAR=true SETUP_LOG_FILE="$tmp/recovery-test.log"
mkdir -p "$HOME" "$tmp/repo/backups/recovery"
printf 'one\n' > "$HOME/.first"
printf 'two\n' > "$HOME/.second"
# Підготуємо двооб'єктний знімок через перевірений формат manifest.
id='2026-10-14_10-00-00_300'
snap="$tmp/repo/backups/recovery/$id"
mkdir -p "$snap/data"
cp "$HOME/.first" "$snap/data/first"
cp "$HOME/.second" "$snap/data/second"
printf 'first\t%s\nsecond\t%s\n' "$HOME/.first" "$HOME/.second" > "$snap/manifest.tsv"
python3 "$tmp/repo/tools/recovery_safe.py" create "$snap" >/dev/null
printf 'changed1\n' > "$HOME/.first"
printf 'changed2\n' > "$HOME/.second"
plan="$("$tmp/repo/backup-install_manager.sh" recovery plan "$id" first)"
[[ "$plan" == *"RESTORE first -> $HOME/.first"* && "$plan" != *'RESTORE second'* ]] || exit 1
[[ "$(cat "$HOME/.first")" == changed1 ]] || exit 1
if "$tmp/repo/backup-install_manager.sh" --yes recovery restore "$id" unknown >/dev/null 2>&1; then exit 1; fi
"$tmp/repo/backup-install_manager.sh" --yes recovery restore "$id" first >/dev/null
[[ "$(cat "$HOME/.first")" == one && "$(cat "$HOME/.second")" == changed2 ]] || exit 1
printf '[PASS] test-recovery-selective\n'
