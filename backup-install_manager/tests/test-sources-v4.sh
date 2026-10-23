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
cat > "$ROOT_DIR/config/dotfiles.conf" <<'CONF'
[editors]
first | home | ~/.config/editor
second | home | ~/.config/shell
CONF
sources_load
[[ ${#SRC_ROWS[@]} == 2 ]]
sources_find first
[[ "$PATH_LIVE" == "$HOME/.config/editor" ]]
printf 'third | home | ~/.config/editor\n' >> "$ROOT_DIR/config/dotfiles.conf"
if sources_load >/dev/null 2>&1; then exit 1; fi
sed -i '$d' "$ROOT_DIR/config/dotfiles.conf"
printf 'third | home | ~/.config/editor/lua\n' >> "$ROOT_DIR/config/dotfiles.conf"
if sources_load >/dev/null 2>&1; then exit 1; fi
sed -i '$d' "$ROOT_DIR/config/dotfiles.conf"
sources_add fourth home "${literal_tilde}.gitconfig" editors >/dev/null
sources_load
[[ ${#SRC_ROWS[@]} == 3 ]]
[[ "$(path_repo_for home "${literal_tilde}.config/editor")" == "$ROOT_DIR/dotfiles/home/.config/editor" ]]
echo '[PASS] test-sources-v4'
