#!/usr/bin/env bash
# shellcheck disable=SC2034
MODULE_ID="font"
MODULE_TITLE="Fonts"
MODULE_ORDER=40
PACMAN_PACKAGES=(ttf-nerd-fonts-symbols-mono)
AUR_PACKAGES=()
GITHUB_ITEMS=()

CONFIG_ITEMS=(
    fonts
    fonts-conf
)

hook_update_font_cache() {
    command -v fc-cache >/dev/null || return 0
    [[ "${DRY_RUN:-false}" == true ]] && {
        log info '[DRY-RUN] fc-cache -fv'
        return 0
    }
    fc-cache -fv >/dev/null && log ok 'Кеш шрифтів оновлено'
}
