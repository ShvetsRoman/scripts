#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="base"
MODULE_TITLE="Base"
MODULE_ORDER=10
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    base-devel
    git
    curl
    wget
    rsync
    unzip
    zip
    tar
    p7zip
    unace
    unrar
)
AUR_PACKAGES=(
)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
