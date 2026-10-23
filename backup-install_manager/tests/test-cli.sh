#!/usr/bin/env bash
literal_tilde="$(printf '%s/' '~')"
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -a -- "$repo" "$tmp/setup-manager"
repo="$tmp/setup-manager"
mkdir -p "$tmp/home"
export HOME="$tmp/home"
printf '[test]\n' > "$repo/config/dotfiles.conf"
printf 'alpha | home | ~/.alpha\n' >> "$repo/config/dotfiles.conf"
printf 'first\n' > "$HOME/.alpha"
expected_version="$(bash -c 'source "$1/src/core/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$repo")"
[[ "$("$repo/backup-install_manager.sh" --version)" == "$expected_version" ]]
"$repo/backup-install_manager.sh" sources validate >/dev/null
"$repo/backup-install_manager.sh" sources add beta home "${literal_tilde}.beta" test >/dev/null
"$repo/backup-install_manager.sh" sources remove beta >/dev/null
"$repo/backup-install_manager.sh" dotfiles backup alpha >/dev/null
[[ "$(cat "$repo/dotfiles/home/.alpha")" == first ]]
printf 'second\n' > "$repo/dotfiles/home/.alpha"
"$repo/backup-install_manager.sh" dotfiles restore alpha >/dev/null
[[ "$(cat "$HOME/.alpha")" == second ]]
# Unknown filters must error before write
if "$repo/backup-install_manager.sh" dotfiles backup not-in-registry >/dev/null 2>&1; then exit 1; fi
# Unknown dotfiles subcommands must print up-to-date usage and return exit code 2.
usage_rc=0
usage_output="$("$repo/backup-install_manager.sh" dotfiles re 2>&1)" || usage_rc=$?
[[ "$usage_rc" == 2 ]] || { printf 'bad dotfiles usage exit: %s\n' "$usage_rc" >&2; exit 1; }
[[ "$usage_output" == *'Невідома команда dotfiles: re'* &&
   "$usage_output" == *'dotfiles backup changed'* &&
   "$usage_output" == *'dotfiles restore'* &&
   "$usage_output" == *'dotfiles plan restore'* ]] || {
    printf 'outdated dotfiles usage:\n%s\n' "$usage_output" >&2; exit 1;
}
[[ "$("$repo/backup-install_manager.sh" dotfiles --help)" == *'dotfiles backup changed'* ]]
# dry-run doesn't create lock after deletion
rm -f "$repo/.setup-manager.lock"
"$repo/backup-install_manager.sh" --dry-run sources add beta home "${literal_tilde}.beta" test >/dev/null
[[ ! -e "$repo/.setup-manager.lock" ]]
if grep -q 'beta' "$repo/config/dotfiles.conf"; then exit 1; fi
# CLI lock contention (no writes)
exec 8>> "$repo/.setup-manager.lock"
flock -n 8
code=0
"$repo/backup-install_manager.sh" sources add beta home "${literal_tilde}.beta" test >/dev/null 2>&1 || code=$?
[[ "$code" == 75 ]] || { printf 'bad contention exit: %s\n' "$code" >&2; exit 1; }
flock -u 8
printf '[PASS] test-cli\n'
