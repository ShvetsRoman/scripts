#!/usr/bin/env bash
# Під час dry-run не викликається ні pacman, ні paru.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
log() { :; }
export PKG_TEST_LOG="$tmp/log"
cat > "$tmp/pacman" <<'MOCK'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >> "$PKG_TEST_LOG"
case "$1" in
    -Qq) printf 'present\n';;
    -Si) for x in "$@"; do [[ "$x" == missing ]] && exit 1; done; exit 0;;
    -S) exit 0;;
    *) exit 3;;
esac
MOCK
cat > "$tmp/paru" <<'MOCK'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >> "$PKG_TEST_LOG"
case "$1" in
    -Si) for x in "$@"; do [[ "$x" == missing ]] && exit 1; done; exit 0;;
    -S) exit 0;;
    *) exit 3;;
esac
MOCK
cat > "$tmp/sudo" <<'MOCK'
#!/usr/bin/env bash
"$@"
MOCK
chmod +x "$tmp/pacman" "$tmp/paru" "$tmp/sudo"
export PATH="$tmp:$PATH"
DRY_RUN=true
pkgs_install pacman present alpha beta
pkgs_install aur alpha
[[ ! -e "$tmp/log" ]]
DRY_RUN=false
pkgs_install pacman present alpha beta
[[ $(grep -c '^pacman -Qq$' "$tmp/log") -eq 1 ]]
[[ $(grep -c '^pacman -Si -- alpha beta$' "$tmp/log") -eq 1 ]]
: > "$tmp/log"
if pkgs_install pacman alpha missing beta; then exit 1; fi
[[ $(grep -c '^pacman -Si -- ' "$tmp/log") -eq 4 ]]
: > "$tmp/log"
pkgs_install aur present alpha beta
[[ $(grep -c '^paru -Si --aur -- alpha beta$' "$tmp/log") -eq 1 ]]
if pkgs_install bogus something; then exit 1; fi
printf '[PASS] test-packages-batch\n'
