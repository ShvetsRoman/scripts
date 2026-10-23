#!/usr/bin/env bash
# Запобіжники файлових операцій перевіряються без системних змін.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/src/recovery/archive.sh"
archive_valid_name good_01.tar.gz
for value in ../evil.tar.gz a..b.tar.gz /tmp/a.tar.gz invalid.zip; do
    if archive_valid_name "$value"; then exit 1; fi
done
grep -Fq '[[ -f "$file" && ! -L "$file" ]]' "$root/src/recovery/archive.sh"
grep -Fq '[[ -f "$hook_file" && ! -L "$hook_file" ]]' "$root/src/hooks/hook_runtime.sh"
printf '[PASS] test-fs-safety-v1435\n'
