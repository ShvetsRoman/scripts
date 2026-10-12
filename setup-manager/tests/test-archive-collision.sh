#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/core.sh
source "$PROJECT_DIR/lib/core.sh"
# shellcheck source=../lib/archive.sh
source "$PROJECT_DIR/lib/archive.sh"
ROOT_DIR="$TEST_DIR/project"
SETUP_ARCHIVE_PREFIX='dotfiles-test'
DRY_RUN=false
setup_confirm() { return 0; }
mkdir -p -- "$ROOT_DIR/dotfiles/.config/app"
printf 'version=1\n' > "$ROOT_DIR/dotfiles/.config/app/config.toml"
archive_create >/dev/null
mapfile -t first_list < <(find "$ROOT_DIR/archives" -maxdepth 1 -name '*.tar.gz' -type f)
((${#first_list[@]} == 1)) || exit 1
first="${first_list[0]}"
printf 'version=2\n' > "$ROOT_DIR/dotfiles/.config/app/config.toml"
archive_create >/dev/null
mapfile -t both < <(find "$ROOT_DIR/archives" -maxdepth 1 -name '*.tar.gz' -type f)
((${#both[@]} == 2)) || { printf '[FAIL] Collision: архів перезаписаний\n'; exit 1; }
[[ "$(tar -xOzf "$first" dotfiles/.config/app/config.toml)" == 'version=1' ]] || exit 1
printf '[PASS] Два архіви за одну секунду не перезаписуються\n'
archive_restore "${first##*/}" >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/.config/app/config.toml")" == 'version=1' ]] || { printf '[FAIL] Archive Restore\n'; exit 1; }
printf '[PASS] Archive Restore відновив початковий вміст\n'
mapfile -t after < <(find "$ROOT_DIR/archives" -maxdepth 1 -name '*.tar.gz' -type f)
((${#after[@]} == 3)) || { printf '[FAIL] Захисний архів відсутній\n'; exit 1; }
found=false
for file in "${after[@]}"; do
    if [[ "$file" != "$first" ]] && [[ "$(tar -xOzf "$file" dotfiles/.config/app/config.toml)" == 'version=2' ]]; then
        found=true
    fi
done
[[ "$found" == true ]] || exit 1
printf '[PASS] Захисний архів зберігає стан перед Restore\n'
