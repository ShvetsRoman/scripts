#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -a -- "$repo" "$tmp/setup-manager"
repo="$tmp/setup-manager"
mkdir -p "$tmp/home"
export HOME="$tmp/home"
printf 'alpha | home | .alpha | .alpha | dotfiles\n' > "$repo/config/sources.conf"
printf 'first\n' > "$HOME/.alpha"
[[ "$("$repo/setup.sh" --version)" == 1.3.0 ]]
"$repo/setup.sh" sources validate >/dev/null
"$repo/setup.sh" sources add beta home .beta .beta >/dev/null
"$repo/setup.sh" sources remove beta >/dev/null
"$repo/setup.sh" dotfiles backup alpha >/dev/null
[[ "$(cat "$repo/dotfiles/.alpha")" == first ]]
printf 'second\n' > "$repo/dotfiles/.alpha"
"$repo/setup.sh" dotfiles restore alpha >/dev/null
[[ "$(cat "$HOME/.alpha")" == second ]]
# Unknown filters must error before write
if "$repo/setup.sh" dotfiles backup not-in-registry >/dev/null 2>&1; then exit 1; fi
# Unknown dotfiles subcommands must print up-to-date usage and return exit code 2.
usage_rc=0
usage_output="$("$repo/setup.sh" dotfiles re 2>&1)" || usage_rc=$?
[[ "$usage_rc" == 2 ]] || { printf 'bad dotfiles usage exit: %s\n' "$usage_rc" >&2; exit 1; }
[[ "$usage_output" == *'Невідома команда dotfiles: re'* &&
   "$usage_output" == *'dotfiles backup changed'* &&
   "$usage_output" == *'dotfiles restore'* &&
   "$usage_output" == *'dotfiles plan restore'* ]] || {
    printf 'outdated dotfiles usage:\n%s\n' "$usage_output" >&2; exit 1;
}
[[ "$("$repo/setup.sh" dotfiles --help)" == *'dotfiles backup changed'* ]]
# dry-run doesn't create lock after deletion
rm -f "$repo/.setup-manager.lock"
"$repo/setup.sh" --dry-run sources add beta home .beta .beta >/dev/null
[[ ! -e "$repo/.setup-manager.lock" ]]
if grep -q 'beta' "$repo/config/sources.conf"; then exit 1; fi
# CLI lock contention (no writes)
exec 8>> "$repo/.setup-manager.lock"
flock -n 8
code=0
"$repo/setup.sh" sources add beta home .beta .beta >/dev/null 2>&1 || code=$?
[[ "$code" == 75 ]] || { printf 'bad contention exit: %s\n' "$code" >&2; exit 1; }
flock -u 8
printf '[PASS] test-cli\n'
