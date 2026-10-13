#!/usr/bin/env bash
# Тести seed.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$ROOT_DIR/lib/path.sh"
# shellcheck source=../lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=../lib/sources_seed.sh
source "$ROOT_DIR/lib/sources_seed.sh"

check() {
    local path="$1" want="$2" got
    got="$(_seed_classify "$path")"
    [[ "$got" == "$want" ]] || { printf '[FAIL] %s: got=%s want=%s\n' "$path" "$got" "$want" >&2; exit 1; }
}

# suggest.
check ".zshrc"             suggest
check ".gitconfig"         suggest
check ".config/nvim"       suggest
check ".config/kitty"      suggest
check ".config/kdeglobals" suggest

# skip.
check ".ssh"               skip
check ".gnupg"             skip
check ".zsh_history"       skip
check ".cache"             skip
check ".config/google-chrome" skip
check "Downloads"          skip
check "Videos"             skip

# ask.
check ".config/somenewtool"    ask
check ".config/unknown-1"      ask

printf '[PASS] test-seed\n'
