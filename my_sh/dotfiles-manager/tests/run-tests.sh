#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/tests/test_syntax.sh"
"$ROOT/tests/test_config.sh"
"$ROOT/tests/test_globals.sh"
"$ROOT/tests/test_validation.sh"
"$ROOT/tests/test_status.sh"
"$ROOT/tests/test_shellcheck.sh"

printf 'Усі доступні тести пройдено.\n'
