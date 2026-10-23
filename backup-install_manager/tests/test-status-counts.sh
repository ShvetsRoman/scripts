#!/usr/bin/env bash
# Regression: вкладені NEW/DEL, коментарі та підсумок (status/diff/verify).
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf '[FAIL] test-status-counts: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" SETUP_NO_CLEAR=true
cp -a -- "$PROJECT_DIR" "$tmp/setup-manager"
repo="$tmp/setup-manager"
# Не допускаємо впливу користувацьких dotfiles на тестові лічильники.
rm -rf -- "$repo/dotfiles"
mkdir -p -- "$repo/dotfiles"
mkdir -p "$HOME/.config/nvim/home-dir/deep" \
         "$repo/dotfiles/home/.config/nvim/repo-dir/deep" \
         "$repo/dotfiles/home/.config/untracked"
cat > "$repo/config/dotfiles.conf" <<'REGISTRY'
[test]
zsh | home | ~/.zshrc
nvim | home | ~/.config/nvim
same | home | ~/.same
missing | home | ~/.neither
REGISTRY
printf 'home-only\n' > "$HOME/.zshrc"
printf 'same\n' > "$HOME/.same"
printf 'same\n' > "$repo/dotfiles/home/.same"
printf 'new\n' > "$HOME/.config/nvim/home.lua"
printf 'old\n' > "$repo/dotfiles/home/.config/nvim/repo.lua"
printf 'new nested\n' > "$HOME/.config/nvim/home-dir/deep/home.lua"
printf 'old nested\n' > "$repo/dotfiles/home/.config/nvim/repo-dir/deep/repo.lua"
printf 'extra\n' > "$repo/dotfiles/home/.config/untracked/extra"

output="$(bash "$repo/backup-install_manager.sh" dotfiles status)" || fail 'status error on normal differences'
[[ "$output" == *'[CHANGED] nvim — є відмінності між HOME і dotfiles'* ]] || fail 'CHANGED comment'
[[ "$output" == *'[NEW] zsh — є в HOME, немає в dotfiles'* ]] || fail 'top-level NEW comment'
[[ "$output" == *'[NEW] nvim/home.lua — є в HOME, немає в dotfiles'* ]] || fail 'nested NEW comment'
[[ "$output" == *'[DEL] nvim/repo.lua — є в dotfiles, немає в HOME'* ]] || fail 'nested DEL comment'
[[ "$output" == *'[NEW] nvim/home-dir/ — є в HOME, немає в dotfiles'* ]] || fail 'nested NEW dir'
[[ "$output" == *'[DEL] nvim/repo-dir/ — є в dotfiles, немає в HOME'* ]] || fail 'nested DEL dir'
[[ "$output" != *'nvim/home-dir/deep/home.lua'* ]] || fail 'HOME directory contents should not be counted separately'
[[ "$output" != *'nvim/repo-dir/deep/repo.lua'* ]] || fail 'repo directory contents should not be counted separately'
[[ "$output" == *'[UNTRACKED] home/.config/untracked — є в dotfiles, немає запису в dotfiles.conf'* ]] || fail 'UNTRACKED comment'
[[ "$output" == *'[MISSING] missing — немає ні в HOME, ні в dotfiles'* ]] || fail 'missing on both sides'
[[ "$output" == *'Status: однакових 1, змінених 1, тільки в HOME 3, тільки в dotfiles 2, відсутніх 1, поза реєстром 1, помилок 0'* ]] || fail 'status wrong counters'

verify="$(bash "$repo/backup-install_manager.sh" dotfiles verify)" || fail 'verify error on differences'
[[ "$verify" == *'Verify: записів 4, однакових 1, змінених 1, тільки в HOME 3, тільки в dotfiles 2, відсутніх 1, помилок 0'* ]] || fail 'verify wrong counters'
diff="$(bash "$repo/backup-install_manager.sh" dotfiles diff)" || fail 'diff error on differences'
[[ "$diff" == *'Diff: змінених 1, тільки в HOME 3, тільки в dotfiles 2, відсутніх 1, помилок 0 (з 4 записів)'* ]] || fail 'diff wrong counters'

# Зворотна ситуація: найвищий рівень DEL також має рахуватися.
rm -f "$HOME/.zshrc"
printf 'repo-only\n' > "$repo/dotfiles/home/.zshrc"
output="$(bash "$repo/backup-install_manager.sh" dotfiles status)" || fail 'status error on reversed missing source'
[[ "$output" == *'[DEL] zsh — є в dotfiles, немає в HOME'* ]] || fail 'top-level DEL comment'
[[ "$output" == *'Status: однакових 1, змінених 1, тільки в HOME 2, тільки в dotfiles 3, відсутніх 1, поза реєстром 1, помилок 0'* ]] || fail 'top-level DEL not counted'

# --no-color не повинен змінювати зміст підсумків.
output="$(SETUP_COLOR=always bash "$repo/backup-install_manager.sh" --no-color dotfiles status)" || fail '--no-color returned error'
[[ "$output" != *$'\033['* ]] || fail '--no-color outputs ANSI'
[[ "$output" == *'поза реєстром 1, помилок 0'* ]] || fail '--no-color broke counters'
printf '[PASS] test-status-counts\n'
