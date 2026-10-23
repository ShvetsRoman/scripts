#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
cp -a -- "$PROJECT_DIR" "$tmp/repo"
export SETUP_LOG_FILE="$tmp/session.log" SETUP_NO_CLEAR=true
"$tmp/repo/backup-install_manager.sh" sources validate >/dev/null
[[ -f "$SETUP_LOG_FILE" ]] || exit 1
# Час, PID, run, severity: мінімальна перевірка структури.
grep -Eq '^\[20[0-9]{2}-[0-9]{2}-[0-9]{2}T.*\] \[pid=[0-9]+\] \[run=.*\] \[OK\]' "$SETUP_LOG_FILE" || exit 1
[[ "$("$tmp/repo/backup-install_manager.sh" logs path)" == "$SETUP_LOG_FILE" ]] || exit 1
out="$("$tmp/repo/backup-install_manager.sh" logs tail 1)"
[[ "$out" == *'dotfiles.conf'* ]] || exit 1
if "$tmp/repo/backup-install_manager.sh" logs tail 0 >/dev/null 2>&1; then exit 1; fi
printf '[PASS] test-logs-v3\n'
