#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="multimedia"
MODULE_TITLE="Multimedia"
MODULE_ORDER=120
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    vlc
    ffmpeg
    ffmpegthumbnailer
    vlc-plugins-all
)
AUR_PACKAGES=(
    deadbeef
)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
