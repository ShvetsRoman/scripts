#!/usr/bin/env bash
# Перевірка файлів, потрібних після розпакування релізу.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -d "$root/dotfiles" && -f "$root/dotfiles/.keep" ]]
[[ -d "$root/src/core" && -d "$root/src/packages" && -d "$root/src/recovery" ]]
# shellcheck source=../src/core/version.sh
source "$root/src/core/version.sh"
for document in "$root/README.md" "$root/docs/architecture.md" "$root/docs/CHANGELOG.md"; do
    grep -Fq "$SETUP_VERSION" "$document"
done
printf '[PASS] test-release-layout-v1430\n'
