#!/usr/bin/env bash
# Тести sources.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$ROOT_DIR/lib/path.sh"
# shellcheck source=../lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/config"
: > "$ROOT_DIR/config/sources.conf"
HOME="$tmp/home"; mkdir -p "$HOME"

sources_add home ".zshrc" ".zshrc" dotfiles >/dev/null
sources_load
((${#SRC_ROWS[@]} == 1)) || { printf '[FAIL] add\n' >&2; exit 1; }

sources_parse "${SRC_ROWS[0]}"
[[ "$S_MODE" == home && "$S_SRC" == ".zshrc" ]] || { printf '[FAIL] parse\n' >&2; exit 1; }
[[ "$(sources_abs home '.zshrc')" == "$HOME/.zshrc" ]] || { printf '[FAIL] abs\n' >&2; exit 1; }

if sources_add home ".other" ".zshrc" 2>/dev/null; then printf '[FAIL] дублікат\n' >&2; exit 1; fi

sources_remove ".zshrc" >/dev/null
sources_load
((${#SRC_ROWS[@]} == 0)) || { printf '[FAIL] remove\n' >&2; exit 1; }

mkdir -p "$tmp/real" "$tmp/lnk"
ln -s "$tmp/real" "$tmp/lnk/x"
if sources_add abs "$tmp/lnk/x" "bad" 2>/dev/null; then printf '[FAIL] symlink\n' >&2; exit 1; fi

printf '[PASS] test-sources\n'
