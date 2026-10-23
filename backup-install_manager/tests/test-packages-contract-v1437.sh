#!/usr/bin/env bash
# Існуючі регресії Packages/Configs залишаються обов'язковими.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for name in test-configs-executor-v1428 test-configs-dedup-v1415 test-packages-validation-v1414 test-packages-config-failure-v148; do
    [[ -s "$root/tests/$name.sh" ]]
    grep -Fq "$name" "$root/tests/run-tests.sh"
done
printf '[PASS] test-packages-contract-v1437\n'
