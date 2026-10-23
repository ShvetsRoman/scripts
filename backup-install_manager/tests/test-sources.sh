#!/usr/bin/env bash
literal_tilde="$(printf '%s/' '~')"
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/src/core/ui.sh"
ui_init_colors
source "$ROOT_DIR/src/core/path.sh"
source "$ROOT_DIR/src/dotfiles/sources.sh"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; HOME="$tmp/home"
mkdir -p "$ROOT_DIR/config" "$HOME"
printf '[shell]\n' > "$ROOT_DIR/config/dotfiles.conf"
sources_add zsh home "${literal_tilde}.zshrc" shell >/dev/null
sources_load
[[ ${#SRC_ROWS[@]} == 1 ]]
sources_find zsh
[[ "$PATH_LIVE" == "$HOME/.zshrc" ]]
[[ "$PATH_REPO" == "$ROOT_DIR/dotfiles/home/.zshrc" ]]
if sources_add zsh home "${literal_tilde}.other" shell 2>/dev/null; then exit 1; fi
sources_remove zsh >/dev/null
sources_load
[[ ${#SRC_ROWS[@]} == 0 ]]
if sources_add bad home '.relative' shell 2>/dev/null; then exit 1; fi
printf '[PASS] test-sources\n'
