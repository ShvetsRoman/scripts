#!/usr/bin/env bash
# Перевірка CLI без входу в інтерактивне меню.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/src/core/version.sh"
[[ "$(SETUP_TEST_MODE=true bash "$root/backup-install_manager.sh" --version)" == "$SETUP_VERSION" ]]
output="$(SETUP_TEST_MODE=true bash "$root/backup-install_manager.sh" --help)"
[[ "$output" == *'dotfiles backup changed'* ]]
[[ "$output" == *'recovery list|verify'* ]]
printf '[PASS] test-cli-contract-v1439\n'
