#!/usr/bin/env bash
set -Eeuo pipefail
project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/repo/dotfiles" "$fixture/home" "$fixture/repo/config"
printf 'BACKUP_FILES=("equal" "only-home" "only-repo" "changed" "absent")\nBACKUP_DIRS=()\n' > "$fixture/repo/config/dotfiles.conf"
printf 'equal\n' > "$fixture/home/equal"
printf 'equal\n' > "$fixture/repo/dotfiles/equal"
printf 'home\n' > "$fixture/home/only-home"
printf 'repo\n' > "$fixture/repo/dotfiles/only-repo"
printf 'home\n' > "$fixture/home/changed"
printf 'repo\n' > "$fixture/repo/dotfiles/changed"
output="$(bash -c '''
    source "$1/lib/ui.sh"
    source "$1/lib/core.sh"
    source "$1/lib/dotfiles.sh"
    ROOT_DIR="$2"
    HOME="$3"
    dotfiles_status
''' bash "$project" "$fixture/repo" "$fixture/home" || [[ "$?" == 1 ]])"
[[ "$output" == *'[OK] equal'* ]]
[[ "$output" == *'[NEW] only-home — є в HOME, але відсутній у dotfiles'* ]]
[[ "$output" == *'[DEL] only-repo — є в dotfiles, але відсутній у HOME'* ]]
[[ "$output" == *'[CHANGED] changed'* ]]
[[ "$output" == *'[MISSING] absent'* ]]
[[ "$output" != *'[OK] [OK]'* ]]
[[ "$output" != *'[WARN] [DEL]'* ]]
printf '[PASS] Dotfiles: статуси OK/NEW/DEL/CHANGED/MISSING\n'
