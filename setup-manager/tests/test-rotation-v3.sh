#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$PROJECT_DIR/lib/path.sh"
# shellcheck source=../lib/maintenance.sh
source "$PROJECT_DIR/lib/maintenance.sh"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
base="$ROOT_DIR/backups/dotfiles"
mkdir -p "$base"
for i in 01 02 03 04; do mkdir "$base/2026-10-${i}_10-00-00_123"; done
setup_confirm() { return 0; }
DRY_RUN=true
maintenance_rotate dotfiles 2 >/dev/null
[[ "$(find "$base" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 4 ]] || exit 1
DRY_RUN=false
maintenance_rotate dotfiles 2 >/dev/null
[[ "$(find "$base" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 2 ]] || exit 1
[[ -d "$base/2026-10-04_10-00-00_123" && -d "$base/2026-10-03_10-00-00_123" ]] || exit 1
printf '[PASS] test-rotation-v3\n'
