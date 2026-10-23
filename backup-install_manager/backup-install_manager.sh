#!/usr/bin/env bash
# Єдина точка входу Setup Manager.
set -Eeuo pipefail
umask 077

# shellcheck source=src/core/bootstrap.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/src/core/bootstrap.sh"
bootstrap_main "$@"
