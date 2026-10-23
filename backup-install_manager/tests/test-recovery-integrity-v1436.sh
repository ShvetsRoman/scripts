#!/usr/bin/env bash
# Перевірка контрактів rollback у system_restore.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
file="$root/src/recovery/system_restore.sh"
grep -Fq '"$backup_dir/original"' "$file"
grep -Fq 'перевірка запису не пройдена, виконую rollback' "$file"
grep -Fq '"${root[@]}" rm -f -- "$tmp"' "$file"
grep -Fq 'if ! path_ok_abs "$dst"' "$file"
printf '[PASS] test-recovery-integrity-v1436\n'
