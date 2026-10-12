#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="dev"
MODULE_TITLE="Development"
MODULE_ORDER=50
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    gcc
    make
    cmake
    python
    python-pip
    nodejs
    npm
    shellcheck
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
