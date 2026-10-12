#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="shell"
MODULE_TITLE="Shell"
MODULE_ORDER=30
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    zsh
    zsh-completions
    zsh-syntax-highlighting
    zsh-autocomplete
    zsh-autosuggestions
    starship
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
    "zsh|home|.zshrc|.zshrc"
    "zsh-alias|home|.zsh_alias.zsh|.zsh_alias.zsh"
    "zsh-path|home|.zsh_path.zsh|.zsh_path.zsh"
    "starship|home|.config/starship|.config/starship"
)
