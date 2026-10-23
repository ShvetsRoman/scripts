#!/usr/bin/env bash
# Звіти лише читають чинний реєстр та не змінюють систему.

report_modules() {
    local action="${1:-list}" id target dep count=0
    (($#)) && shift
    case "$action" in
        list)
            (($# == 0)) || return 2
            registry_show ;;
        info)
            (($# == 1)) && registry_valid "$1" || { printf '[ERROR] modules info ID\n' >&2; return 2; }
            id="$1"
            printf 'Модуль: %s\nНазва: %s\nPacman: %s\nAUR: %s\nConfigs: %s\nHooks: %s\n' \
                "$id" "$(registry_title "$id")" "${PACKAGE_PACMAN[$id]:-}" "${PACKAGE_AUR[$id]:-}" \
                "${PACKAGE_CONFIGS[$id]:-}" "${PACKAGE_HOOKS[$id]:-}" ;;
        deps|reverse)
            (($# == 1)) && registry_valid "$1" || { printf '[ERROR] modules %s ID\n' "$action" >&2; return 2; }
            id="$1"
            if [[ "$action" == deps ]]; then
                printf 'Залежності %s:\n' "$id"
                for target in ${PACKAGE_DEPENDS[$id]:-}; do printf '  %s\n' "$target"; done
            else
                printf 'Залежать від %s:\n' "$id"
                for target in "${PACKAGE_IDS[@]}"; do
                    for dep in ${PACKAGE_DEPENDS[$target]:-}; do
                        if [[ "$dep" == "$id" ]]; then printf '  %s\n' "$target"; fi
                    done
                done
            fi ;;
        stats)
            (($# == 0)) || return 2
            printf 'Модулів: %s\n' "${#PACKAGE_IDS[@]}"
            for id in "${PACKAGE_IDS[@]}"; do
                [[ -n "${PACKAGE_PACMAN[$id]:-}${PACKAGE_AUR[$id]:-}" ]] && count=$((count + 1))
            done
            printf 'З пакетами: %s\nБез пакетів: %s\n' "$count" "$(( ${#PACKAGE_IDS[@]} - count ))" ;;
        plan)
            (($# == 0)) || return 2
            printf 'Порядок модулів за залежностями (без запуску):\n'
            registry_graph_order ;;
        *) printf '[ERROR] modules list|info ID|deps ID|reverse ID|stats|plan\n' >&2; return 2 ;;
    esac
}

report_main() {
    local action="${1:-summary}"
    (($#)) && shift
    (($# == 0)) || return 2
    case "$action" in
        summary)
            printf 'Setup Manager %s\n' "$SETUP_VERSION"
            report_modules stats ;;
        modules) report_modules stats ;;
        *) printf '[ERROR] report summary|modules\n' >&2; return 2 ;;
    esac
}
