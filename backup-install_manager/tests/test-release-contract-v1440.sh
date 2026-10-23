#!/usr/bin/env bash
# Інваріанти пакування і документації фінального релізу.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$root/dotfiles/.keep" ]]
[[ ! -e "$root/logs/setup-tests.log" ]]
source "$root/src/core/version.sh"
[[ "$SETUP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-preview|-rc[0-9]+)?$ ]]
for doc in README.md docs/architecture.md docs/CHANGELOG.md; do
    grep -Fq "$SETUP_VERSION" "$root/$doc"
done
printf '[PASS] test-release-contract-v1440\n'
