#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="office"
MODULE_TITLE="Office"
MODULE_ORDER=80
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    libreoffice-still
    libreoffice-still-uk
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
