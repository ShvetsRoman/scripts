#!/usr/bin/env bash
# Безпечна одноразова міграція без перезапису даних.
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
repo="$tmp/project"
mkdir -p "$repo/src/core" "$repo/src/dotfiles" "$repo/dotfiles" "$repo/tools" "$repo/config" "$repo/dotfiles/.config" "$repo/dotfiles/etc/samba" "$tmp/user"
cp -- "$BASE/src/core/path.sh" "$BASE/src/core/ui.sh" "$repo/src/core/"
cp -- "$BASE/src/dotfiles/sources.sh" "$repo/src/dotfiles/"
cp -- "$BASE/tools/migrate-dotfiles-v1410.sh" "$repo/tools/"
cat > "$repo/config/dotfiles.conf" <<'CONF'
[terminal]
kitty | home | ~/.config/kitty
[samba]
samba | system | /etc/samba/smb.conf
CONF
printf 'kitty\n' > "$repo/dotfiles/.config/kitty"
printf 'samba\n' > "$repo/dotfiles/etc/samba/smb.conf"
HOME="$tmp/user" bash "$repo/tools/migrate-dotfiles-v1410.sh" --dry-run >/dev/null
[[ -f "$repo/dotfiles/.config/kitty" && ! -e "$repo/dotfiles/home/.config/kitty" ]]
HOME="$tmp/user" bash "$repo/tools/migrate-dotfiles-v1410.sh" --apply >/dev/null
[[ "$(cat "$repo/dotfiles/home/.config/kitty")" == kitty ]]
[[ "$(cat "$repo/dotfiles/system/etc/samba/smb.conf")" == samba ]]
[[ ! -e "$repo/dotfiles/.config/kitty" && ! -e "$repo/dotfiles/etc/samba/smb.conf" ]]
[[ $(find "$repo/archives" -type f -name 'dotfiles-before-v1410-*.tar.gz' | wc -l) == 1 ]]
HOME="$tmp/user" bash "$repo/tools/migrate-dotfiles-v1410.sh" --apply >/dev/null
[[ $(find "$repo/archives" -type f | wc -l) == 1 ]]
printf '[PASS] test-migration-v1410\n'
