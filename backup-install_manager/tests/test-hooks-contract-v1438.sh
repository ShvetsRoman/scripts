#!/usr/bin/env bash
# Перевірка зовнішнього hook runtime та обов'язкового контексту.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq ': "${SETUP_ROOT:?Не задано SETUP_ROOT}"' "$root/src/hooks/hook_runtime.sh"
grep -Fq 'source "$hook_file"' "$root/src/hooks/hook_runtime.sh"
grep -Fq 'hook_main' "$root/src/hooks/hook_runtime.sh"
grep -Fq 'test-hook-isolation-v1433' "$root/tests/run-tests.sh"
printf '[PASS] test-hooks-contract-v1438\n'
