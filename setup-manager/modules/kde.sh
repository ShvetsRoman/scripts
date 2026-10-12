#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="kde"
MODULE_TITLE="KDE"
MODULE_ORDER=90
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    ark
    colord-kde
    kaccounts-integration
    kaccounts-providers
    kdeconnect
    kdenetwork-filesharing
    kwalletmanager
    dolphin-plugins
    kompare
    kimageformats
    qt5-imageformats
    kdesdk-thumbnailers
    ffmpegthumbs
    taglib
    audiocd-kio
    kio-gdrive
    kvantum
    kcalc
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
