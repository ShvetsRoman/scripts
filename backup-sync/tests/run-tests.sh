#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

fail=0

printf '== Bash syntax ==\n'
while IFS= read -r -d '' file; do
    if bash -n "$file"; then
        printf '[PASS] %s\n' "${file#"$ROOT_DIR"/}"
    else
        printf '[FAIL] %s\n' "${file#"$ROOT_DIR"/}"
        fail=1
    fi
done < <(find "$ROOT_DIR" -type f -name '*.sh' -print0)

printf '\n== Required files ==\n'
required=(
    "backup-sync.sh"
    "config/config.conf"
    "config/exclude.conf"
    "lib/globals.sh"
    "lib/logging.sh"
    "lib/utils.sh"
    "lib/args.sh"
    "lib/ssh.sh"
    "lib/rsync.sh"
    "lib/verify.sh"
    "lib/cleanup.sh"
)

for rel in "${required[@]}"; do
    if [[ -e "$ROOT_DIR/$rel" ]]; then
        printf '[PASS] %s\n' "$rel"
    else
        printf '[FAIL] %s\n' "$rel"
        fail=1
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    printf '\n== ShellCheck ==\n'
    if command -v shellcheck >/dev/null 2>&1; then
        if (
            cd "$ROOT_DIR"
            shellcheck -x \
                backup-sync.sh \
                tests/run-tests.sh
        ); then
            printf '[PASS] ShellCheck\n'
        else
            printf '[FAIL] ShellCheck\n'
            fail=1
        fi
else
    printf '[SKIP] ShellCheck не встановлений.\n'
fi
else
    printf '\n[SKIP] ShellCheck не встановлений.\n'
fi

printf '\n== VERIFY summary ==\n'
if grep -q 'CHANGED :' "$ROOT_DIR/lib/rsync.sh" && \
   grep -q 'VERIFY завершено: знайдено відмінності.' "$ROOT_DIR/lib/rsync.sh" && \
   grep -q 'CHANGED_DIRS' "$ROOT_DIR/lib/verify.sh"; then
    printf '[PASS] VERIFY має окремий CHANGED стан\n'
else
    printf '[FAIL] VERIFY CHANGED summary не знайдено\n'
    fail=1
fi

printf '\n== CLI flags ==\n'
if "$ROOT_DIR/backup-sync.sh" --help | grep -q -- '--no-space-check'; then
    printf '[PASS] --no-space-check у help\n'
else
    printf '[FAIL] --no-space-check відсутній у help\n'
    fail=1
fi

exit "$fail"
