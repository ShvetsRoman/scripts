#!/usr/bin/env bash
# shellcheck disable=SC2034
# kde — KDE-інтеграція, kio, ark, dolphin-plugins.
MODULE_ID="kde"
MODULE_TITLE="KDE"
MODULE_ORDER=90
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
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=()
