#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; HOME="$tmp/user"
mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/dotfiles" "$HOME"
# shellcheck source=/dev/null
source "$root/src/core/ui.sh"
ui_init_colors
# shellcheck source=/dev/null
source "$root/src/core/path.sh"
# shellcheck source=/dev/null
source "$root/src/dotfiles/sources.sh"
cat > "$ROOT_DIR/config/dotfiles.conf" <<'CONF'
[shell]
zsh | home | ~/.zshrc
starship | home | ${HOME}/.config/starship
[system]
samba | system | /etc/samba/smb.conf
[other]
special | | /opt/program/config.conf
CONF
sources_load
[[ "${#SRC_ROWS[@]}" == 4 && "${#DOTFILES_GROUPS[@]}" == 3 ]]
sources_find zsh
[[ "$PATH_LIVE" == "$HOME/.zshrc" && "$PATH_REPO" == "$ROOT_DIR/dotfiles/home/.zshrc" ]]
sources_find starship
[[ "$PATH_LIVE" == "$HOME/.config/starship" && "$PATH_REPO" == "$ROOT_DIR/dotfiles/home/.config/starship" ]]
sources_find samba
[[ "$PATH_LIVE" == /etc/samba/smb.conf && "$PATH_REPO" == "$ROOT_DIR/dotfiles/system/etc/samba/smb.conf" ]]
sources_find special
[[ "$PATH_LIVE" == /opt/program/config.conf && "$PATH_REPO" == "$ROOT_DIR/dotfiles/opt/program/config.conf" ]]
if path_resolve home .zshrc; then exit 1; fi
if path_resolve home '$USER/.zshrc'; then exit 1; fi
if path_resolve system /root/unsafe; then exit 1; fi
if path_resolve "" /etc/passwd; then exit 1; fi
if path_resolve "" /etc; then exit 1; fi
if path_resolve '' ../relative; then exit 1; fi
printf '\nold | home | .old | .old | dotfiles\n' >> "$ROOT_DIR/config/dotfiles.conf"
if sources_load >/dev/null 2>&1; then exit 1; fi
printf '[PASS] test-path-registry-v1410\n'
