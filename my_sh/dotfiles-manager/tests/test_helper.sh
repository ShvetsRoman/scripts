#!/usr/bin/env bash

set -Eeuo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$TESTS_DIR/.." && pwd)"

# shellcheck source=../lib/globals.sh
source "$ROOT_DIR/lib/globals.sh"
# shellcheck source=../lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
# shellcheck source=../lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=../lib/status.sh
source "$ROOT_DIR/lib/status.sh"
