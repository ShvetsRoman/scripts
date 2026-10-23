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
    "lib/remote_lock.sh"
    "tests/functional.sh"
    "tests/lint.sh"
    ".shellcheckrc"
)

for rel in "${required[@]}"; do
    if [[ -e "$ROOT_DIR/$rel" ]]; then
        printf '[PASS] %s\n' "$rel"
    else
        printf '[FAIL] %s\n' "$rel"
        fail=1
    fi
done

printf '\n== ShellCheck ==\n'
if command -v shellcheck >/dev/null 2>&1; then
    # lib/*.sh НЕ перевіряються окремо: змінні з globals.sh «не використовуються» в ньому самому
    # (SC2034), бо потрібні іншим файлам. lint.sh іде від backup-sync.sh через `source`-директиви.
    if "$ROOT_DIR/tests/lint.sh"; then
        printf '[PASS] ShellCheck\n'
    else
        printf '[FAIL] ShellCheck\n'
        fail=1
    fi
else
    printf '[SKIP] ShellCheck не встановлений (tests/lint.sh запустіть там, де він є).\n'
fi

printf '\n== CLI flags ==\n'
help_text="$("$ROOT_DIR/backup-sync.sh" --help)"
for flag in --no-space-check --max-delete --allow-empty; do
    if grep -q -- "$flag" <<<"$help_text"; then
        printf '[PASS] %s у help\n' "$flag"
    else
        printf '[FAIL] %s відсутній у help\n' "$flag"
        fail=1
    fi
done

printf '\n== Functional (заглушки ssh/rsync) ==\n'
if "$ROOT_DIR/tests/functional.sh"; then
    printf '[PASS] functional.sh\n'
else
    printf '[FAIL] functional.sh\n'
    fail=1
fi

exit "$fail"
