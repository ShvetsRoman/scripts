#!/usr/bin/env bash
# Тести archive.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$ROOT_DIR/lib/path.sh"
# shellcheck source=../lib/fs.sh
source "$ROOT_DIR/lib/fs.sh"
# shellcheck source=../lib/archive.sh
source "$ROOT_DIR/lib/archive.sh"

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR/dotfiles/.config/app" "$ROOT_DIR/archives"
cp -a "$(dirname -- "${BASH_SOURCE[0]}")/../tools" "$ROOT_DIR/"

printf 'v1\n' > "$ROOT_DIR/dotfiles/.config/app/config"
setup_confirm() { return 0; }
DRY_RUN=false; SETUP_ARCHIVE_PREFIX="test"

archive_create >/dev/null
mapfile -t files < <(find "$ROOT_DIR/archives" -maxdepth 1 -name '*.tar.gz' -type f)
((${#files[@]} == 1)) || { printf '[FAIL] create\n' >&2; exit 1; }

first="${files[0]}"
printf 'v2\n' > "$ROOT_DIR/dotfiles/.config/app/config"
archive_create >/dev/null
mapfile -t both < <(find "$ROOT_DIR/archives" -maxdepth 1 -name '*.tar.gz' -type f)
((${#both[@]} == 2)) || { printf '[FAIL] колізія\n' >&2; exit 1; }

archive_restore "$(basename "$first")" >/dev/null
[[ "$(cat "$ROOT_DIR/dotfiles/.config/app/config")" == v1 ]] || { printf '[FAIL] restore\n' >&2; exit 1; }

if archive_restore "../etc" >/dev/null 2>&1; then printf '[FAIL] traversal\n' >&2; exit 1; fi

# Не публікувати архів, який validator не зможе прочитати (symlink).
ln -s /etc/passwd "$ROOT_DIR/dotfiles/unsafe-link"
before="$(find "$ROOT_DIR/archives" -type f -name '*.tar.gz' | wc -l)"
if archive_create >/dev/null 2>&1; then
    echo '[FAIL] archive with symlink should be rejected' >&2; exit 1
fi
after="$(find "$ROOT_DIR/archives" -type f -name '*.tar.gz' | wc -l)"
[[ "$before" == "$after" ]] || { echo '[FAIL] invalid archive was published' >&2; exit 1; }

printf '[PASS] test-archive\n'
