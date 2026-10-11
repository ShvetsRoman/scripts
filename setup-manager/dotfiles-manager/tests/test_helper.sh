#!/usr/bin/env bash
# ShellCheck без -x не переходить за source до локальних бібліотек.
# shellcheck disable=SC1091

set -Eeuo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$TESTS_DIR/.." && pwd)"

# shellcheck source=../lib/globals.sh
source "$ROOT_DIR/lib/globals.sh"
# shellcheck source=../../lib/ui.sh
source "$ROOT_DIR/../lib/ui.sh"
# shellcheck source=../lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=../lib/status.sh
source "$ROOT_DIR/lib/status.sh"

# echo "PASS: helper - OK"
