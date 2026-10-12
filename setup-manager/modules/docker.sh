#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="docker"
MODULE_TITLE="Docker"
MODULE_ORDER=60
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    docker
    docker-compose
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
