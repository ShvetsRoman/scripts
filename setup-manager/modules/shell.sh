#!/usr/bin/env bash
# shellcheck disable=SC2034
# shell — zsh + автодоповнення + starship.
MODULE_ID="shell"
MODULE_TITLE="Shell"
MODULE_ORDER=30
PACMAN_PACKAGES=(zsh zsh-completions zsh-syntax-highlighting zsh-autocomplete zsh-autosuggestions starship)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=(
    "zsh|home|.zshrc|.zshrc"
    "zsh-alias|home|.zsh_alias.zsh|.zsh_alias.zsh"
    "zsh-path|home|.zsh_path.zsh|.zsh_path.zsh"
    "starship|home|.config/starship|.config/starship"
)

# Hook: зробити zsh типовою.
hook_set_zsh_default() {
    local user="${SUDO_USER:-$USER}"
    local zsh; zsh="$(command -v zsh || true)"
    [[ -n "$zsh" ]] || { log warn 'Zsh не знайдено'; return 0; }
    [[ "$user" == root ]] && { log warn 'chsh для root пропущено'; return 0; }
    local cur; cur="$(getent passwd "$user" | cut -d: -f7)"
    [[ "$cur" == "$zsh" ]] && { log info 'Zsh уже стандартна'; return 0; }
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] chsh -s $zsh $user"; return 0; }
    chsh -s "$zsh" "$user"
}
