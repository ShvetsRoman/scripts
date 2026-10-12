#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="image"
MODULE_TITLE="Image"
MODULE_ORDER=110
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    imagemagick
    gwenview
    gimp
    inkscape
    okular
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
