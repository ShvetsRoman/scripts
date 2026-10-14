#!/usr/bin/env bash
# Regression: colored statuses, nested missing, zero exit on drift / absent.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf '[FAIL] test-status-color: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" SETUP_NO_CLEAR=true
mkdir -p "$HOME/.config/nvim" "$tmp/repo/config" "$tmp/repo/dotfiles/.config/nvim" "$tmp/repo/dotfiles/.config/orphan"
cp -a "$PROJECT_DIR"/. "$tmp/repo/"
printf 'zsh | home | .zshrc | .zshrc | dotfiles\n' > "$tmp/repo/config/sources.conf"
printf 'nvim | home | .config/nvim | .config/nvim | dotfiles\n' >> "$tmp/repo/config/sources.conf"
printf 'same | home | .same | .same | dotfiles\n' >> "$tmp/repo/config/sources.conf"
printf 'equal\n' > "$HOME/.same"
printf 'equal\n' > "$tmp/repo/dotfiles/.same"
printf 'zsh-only\n' > "$HOME/.zshrc"
printf 'same\n' > "$HOME/.config/nvim/shared.lua"
printf 'same\n' > "$tmp/repo/dotfiles/.config/nvim/shared.lua"
printf 'home-only\n' > "$HOME/.config/nvim/home.lua"
printf 'repo-only\n' > "$tmp/repo/dotfiles/.config/nvim/repo.lua"
printf 'orphan\n' > "$tmp/repo/dotfiles/.config/orphan/unused"
# status: no FAIL for differences, full nested detail, unknown file in repo.
output="$(bash "$tmp/repo/setup.sh" dotfiles status)" || fail 'status exit != 0 for drift'
[[ "$output" == *'[NEW] zsh'* ]] || fail 'top-level NEW'
[[ "$output" == *'[CHANGED] nvim'* ]] || fail 'CHANGED'
[[ "$output" == *'[NEW] nvim/home.lua'* ]] || fail 'nested NEW'
[[ "$output" == *'[DEL] nvim/repo.lua'* ]] || fail 'nested DEL'
[[ "$output" == *'[UNTRACKED] .config/orphan'* ]] || fail 'unregistered repo content'
[[ "$output" != *$'\033['* ]] || fail 'ANSI in redirected stdout'
# Verify / diff: ordinary missing and changes must not produce exit code 1.
bash "$tmp/repo/setup.sh" dotfiles verify >/dev/null || fail 'verify returned error for differences'
bash "$tmp/repo/setup.sh" dotfiles diff >/dev/null || fail 'diff returned error for differences'
bash "$tmp/repo/setup.sh" dotfiles plan backup >/dev/null || fail 'plan returned error for differences'
# Named filter and unknown filter must be differentiated.
bash "$tmp/repo/setup.sh" dotfiles status nvim >/dev/null || fail 'valid status filter'
for sub in status verify diff; do
    rc=0
    bash "$tmp/repo/setup.sh" dotfiles "$sub" does-not-exist >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "unknown $sub filter returned $rc instead of 2"
done
# A dotfiles-only top-level item is DEL, still exit 0.
rm -f -- "$HOME/.zshrc"
printf 'repo-file\n' > "$tmp/repo/dotfiles/.zshrc"
output="$(bash "$tmp/repo/setup.sh" dotfiles status)" || fail 'status exit != 0 for repo-only'
[[ "$output" == *'[DEL] zsh'* ]] || fail 'top-level DEL'
# Forced color, opt-out, per status color mapping. Version remains 1.3.0.
export TERM=xterm SETUP_COLOR=always
output="$(bash "$tmp/repo/setup.sh" dotfiles status)" || fail 'force colors'
[[ "$output" == *$'\033[1;33m[CHANGED]'* ]] || fail 'CHANGED not yellow'
[[ "$output" == *$'\033[1;31m[DEL]'* ]] || fail 'DEL not red'
[[ "$output" == *$'\033[0;32m[OK]'* ]] || fail 'OK not green'
output="$(bash "$tmp/repo/setup.sh" dotfiles --no-color status)" || fail '--no-color'
[[ "$output" != *$'\033['* ]] || fail '--no-color ineffective'
output="$(NO_COLOR=1 bash "$tmp/repo/setup.sh" dotfiles status)" || fail 'NO_COLOR'
[[ "$output" != *$'\033['* ]] || fail 'NO_COLOR ineffective'
[[ "$(bash "$tmp/repo/setup.sh" --version)" == 1.3.0 ]] || fail 'version'
printf '[PASS] test-status-color\n'
