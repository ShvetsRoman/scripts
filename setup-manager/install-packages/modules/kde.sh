#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль kde: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="kde"
MODULE_TITLE="KDE"
MODULE_ORDER=90
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK=""

# Пакети офіційних репозиторіїв Arch Linux.
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

# Пакети AUR (через paru).
AUR_PACKAGES=(

)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
)
