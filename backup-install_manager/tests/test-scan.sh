#!/usr/bin/env bash
# Тести dry-run scan/classify.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$ROOT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/dotfiles/sources_seed.sh
source "$ROOT_DIR/src/dotfiles/sources_seed.sh"

check() {
    local path="$1" want="$2" got
    got="$(_scan_classify "$path")"
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

printf '[PASS] test-scan\n'
