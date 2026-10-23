#!/usr/bin/env bash
# Спільне ізольоване середовище виконання hooks.
set -Eeuo pipefail

: "${SETUP_ROOT:?Не задано SETUP_ROOT}"
ROOT_DIR="$SETUP_ROOT"
# Значення читається у hook_main(), який підключається динамічно нижче.
# shellcheck disable=SC2034
DRY_RUN="${SETUP_DRY_RUN:-false}"

# Шляхи й інтерфейс завантажуються тільки один раз у дочірньому процесі.
# shellcheck source=path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=ui.sh
source "$(path_project src/core/ui.sh)"
ui_init_colors

[[ "$#" == 1 ]] || { log error 'Потрібен один аргумент: hook-файл'; exit 2; }
hook_file="$1"
[[ -f "$hook_file" && ! -L "$hook_file" ]] || {
    log error "Hook відсутній або є символічним посиланням: $hook_file"
    exit 2
}

# shellcheck source=/dev/null
source "$hook_file"
if ! declare -F hook_main >/dev/null; then
    log error "Функція hook_main() відсутня: $hook_file"
    exit 2
fi
hook_main
