#!/usr/bin/env bash
# Підтести не повинні запускати clear.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$PROJECT_DIR/src/core/ui.sh"
ui_init_colors
fail() { printf '[FAIL] test-no-clear: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\nprintf "invoked\\n" >> "$CLEAR_MARKER"\n' > "$tmp/bin/clear"
chmod +x "$tmp/bin/clear"
export CLEAR_MARKER="$tmp/calls"
export PATH="$tmp/bin:$PATH"
SETUP_TEST_MODE=true ui_clear
[[ ! -e "$CLEAR_MARKER" ]] || fail 'clear invoked in test mode'
SETUP_TEST_MODE=false SETUP_NO_CLEAR=true ui_clear
[[ ! -e "$CLEAR_MARKER" ]] || fail 'clear invoked with no-clear'
SETUP_TEST_MODE=false SETUP_NO_CLEAR=false ui_clear
[[ -e "$CLEAR_MARKER" ]] || fail 'normal clear disabled'
# Жодна інша бібліотека не повинна напряму викликати clear.
if grep -En '^[[:space:]]*clear([[:space:]]|$)' "$PROJECT_DIR/src/core/"*.sh "$PROJECT_DIR/src/cli/"*.sh "$PROJECT_DIR/src/hooks/"*.sh "$PROJECT_DIR/src/dotfiles/"*.sh "$PROJECT_DIR/src/recovery/"*.sh | grep -v 'src/core/ui.sh:'; then
    fail 'direct clear call'
fi
printf '[PASS] test-no-clear\n'
