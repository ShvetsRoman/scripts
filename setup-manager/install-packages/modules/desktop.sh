#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль desktop: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="desktop"
MODULE_TITLE="Desktop"
MODULE_ORDER=100
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK=""

# Пакети офіційних репозиторіїв Arch Linux.
PACMAN_PACKAGES=(

)

# Пакети AUR (через paru).
AUR_PACKAGES=(
    google-chrome
)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
)
