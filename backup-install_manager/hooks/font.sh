#!/usr/bin/env bash
# Логіка hook; середовище надає src/hooks/hook_runtime.sh.
hook_main() {
    # Hooks модуля font.
    hook_update_font_cache() {
        command -v fc-cache >/dev/null || return 0
        [[ "${DRY_RUN:-false}" == true ]] && {
            log info '[DRY-RUN] fc-cache -fv'
            return 0
        }
        fc-cache -fv >/dev/null && log ok 'Кеш шрифтів оновлено'
    }

    hook_update_font_cache
}
