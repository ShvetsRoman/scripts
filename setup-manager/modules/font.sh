#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="font"
MODULE_TITLE="Fonts"
MODULE_ORDER=40
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    ttf-nerd-fonts-symbols-mono
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
    "font|home|.local/share/fonts|.local/share/fonts"
    "font-conf|home|.fonts.conf|.fonts.conf"
)
