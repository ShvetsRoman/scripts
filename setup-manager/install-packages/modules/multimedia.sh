#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль multimedia: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="multimedia"
MODULE_TITLE="Multimedia"
MODULE_ORDER=120
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK=""

# Пакети офіційних репозиторіїв Arch Linux.
PACMAN_PACKAGES=(
    vlc
    ffmpeg
    ffmpegthumbnailer
    vlc-plugins-all
)

# Пакети AUR (через paru).
AUR_PACKAGES=(
    deadbeef
)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
)
