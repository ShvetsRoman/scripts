#!/usr/bin/env bash
# Регресія: групи dotfiles і фільтрація всіх режимів.
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/repo/config" "$tmp/repo/dotfiles" "$tmp/home"
cp -a "$BASE/src" "$BASE/dotfiles" "$BASE/backup-install_manager.sh" "$tmp/repo/"
cp -a "$BASE/config/setup.conf" "$BASE/config/packages.conf" "$tmp/repo/config/"
cat > "$tmp/repo/config/dotfiles.conf" <<'CONF'
[shell]
a | home | ~/.a
b | home | ~/.b
[editor]
c | home | ~/.c
CONF
printf 'a\n' > "$tmp/home/.a"
printf 'b\n' > "$tmp/home/.b"
printf 'c\n' > "$tmp/home/.c"
run() { HOME="$tmp/home" SETUP_NO_CLEAR=true SETUP_TEST_MODE=true bash "$tmp/repo/backup-install_manager.sh" "$@"; }
run dotfiles groups > "$tmp/groups"
grep -Eq '^shell +2$' "$tmp/groups"
grep -Eq '^editor +1$' "$tmp/groups"
run dotfiles status --group shell > "$tmp/status"
grep -Fq 'a —' "$tmp/status"
if grep -Fq 'c —' "$tmp/status"; then exit 1; fi
run dotfiles verify --group editor > "$tmp/verify"
grep -Fq 'c —' "$tmp/verify"
if grep -Fq 'a —' "$tmp/verify"; then exit 1; fi
run dotfiles plan backup --group shell > "$tmp/plan"
grep -Fq 'усього 2' "$tmp/plan"
run dotfiles backup changed --group shell --dry-run > "$tmp/dry"
if run dotfiles status --group shell c >/dev/null 2>&1; then exit 1; fi
if run dotfiles status --group absent >/dev/null 2>&1; then exit 1; fi
cat >> "$tmp/repo/config/dotfiles.conf" <<'CONF'
[shell]
d | home | ~/.d
CONF
if run sources validate >/dev/null 2>&1; then exit 1; fi
printf '[PASS] test-dotfiles-groups-v149\n'
