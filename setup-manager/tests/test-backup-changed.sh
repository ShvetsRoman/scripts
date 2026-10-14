#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
cp -a -- "$PROJECT_DIR" "$tmp/repo"
export HOME="$tmp/home" SETUP_NO_CLEAR=true
mkdir -p "$HOME" "$tmp/repo/dotfiles"
cat > "$tmp/repo/config/sources.conf" <<'CONF'
a | home | a | a | dotfiles
b | home | b | b | dotfiles
c | home | c | c | dotfiles
d | home | d | d | dotfiles
CONF
printf 'same\n' > "$HOME/a"
printf 'same\n' > "$tmp/repo/dotfiles/a"
printf 'fresh\n' > "$HOME/b"
printf 'stale\n' > "$tmp/repo/dotfiles/b"
printf 'new\n' > "$HOME/c"
# d відсутній і в HOME, і в репозиторії.
output="$("$tmp/repo/setup.sh" dotfiles backup changed)"
[[ "$(cat "$tmp/repo/dotfiles/b")" == fresh && "$(cat "$tmp/repo/dotfiles/c")" == new ]] || exit 1
[[ "$(cat "$tmp/repo/dotfiles/a")" == same ]] || exit 1
[[ "$output" == *'оновлено 2, без змін 1, відсутніх 1, помилок 0'* ]] || { printf '%s\n' "$output" >&2; exit 1; }
# Ідемпотентність: вдруге не повинні з'явитися нові snapshots.
before="$(find "$tmp/repo/backups/dotfiles" -mindepth 1 -maxdepth 1 -type d | wc -l)"
output="$("$tmp/repo/setup.sh" dotfiles backup changed)"
after="$(find "$tmp/repo/backups/dotfiles" -mindepth 1 -maxdepth 1 -type d | wc -l)"
[[ "$before" == "$after" && "$output" == *'оновлено 0, без змін 3'* ]] || exit 1
# Коли нема --sync-delete, зайві файли не вважаються причиною копіювання.
mkdir -p "$HOME/a-dir" "$tmp/repo/dotfiles/a-dir"
printf 'same\n' > "$HOME/a-dir/file"
cp "$HOME/a-dir/file" "$tmp/repo/dotfiles/a-dir/file"
printf 'extra\n' > "$tmp/repo/dotfiles/a-dir/extra"
printf 'dir | home | a-dir | a-dir | dotfiles\n' >> "$tmp/repo/config/sources.conf"
output="$("$tmp/repo/setup.sh" dotfiles backup changed)"
[[ -f "$tmp/repo/dotfiles/a-dir/extra" && "$output" == *'оновлено 0'* ]] || exit 1
output="$("$tmp/repo/setup.sh" --sync-delete dotfiles backup changed)"
[[ ! -e "$tmp/repo/dotfiles/a-dir/extra" ]] || exit 1
[[ "$output" == *'оновлено 1'* ]] || exit 1
printf '[PASS] test-backup-changed\n'
