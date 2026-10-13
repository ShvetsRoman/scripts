#!/usr/bin/env bash
# shellcheck disable=SC2034
# dev — компілятори, мови, лінтери.
MODULE_ID="dev"
MODULE_TITLE="Development"
MODULE_ORDER=50
PACMAN_PACKAGES=(
    gcc
    make
    cmake
    python
    python-pip
    nodejs
    npm
    shellcheck
)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=()
