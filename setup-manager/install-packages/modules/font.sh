#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль font: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="font"
MODULE_TITLE="Fonts"
MODULE_ORDER=40
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK=""

# Пакети офіційних репозиторіїв Arch Linux.
PACMAN_PACKAGES=(
    ttf-nerd-fonts-symbols-mono
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
    "font|home|.local/share/fonts|.local/share/fonts"
    "font-conf|home|.fonts.conf|.fonts.conf"
)
