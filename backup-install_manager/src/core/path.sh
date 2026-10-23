#!/usr/bin/env bash
# Валідація шляхів (без нормалізації небезпечних компонентів).

path_ok_rel() {
    local p="${1:-}"
    [[ -n "$p" && "$p" != *[[:cntrl:]]* && "$p" != /* && "$p" != '.' && "$p" != '..' \
       && "$p" != ../* && "$p" != */.. && "$p" != *'/../'* \
       && "$p" != ./* && "$p" != */. && "$p" != *'/./'* \
       && "$p" != *'//'* ]]
}

# Валідатор синтаксису окремо від перевірки symlink (для реєстру).
path_syntax_abs() {
    local p="${1:-}"
    [[ "$p" != *[[:cntrl:]]* && "$p" == /* && "$p" != *'/../'* && "$p" != */.. \
       && "$p" != *'/./'* && "$p" != */. && "$p" != *'//'* ]]
}

# Жоден наявний компонент не може бути символічним посиланням.
path_ok_abs() {
    local p="${1:-}" cur
    path_syntax_abs "$p" || return 1
    cur="$p"
    while [[ "$cur" != / && -n "$cur" ]]; do
        [[ ! -L "$cur" ]] || return 1
        cur="$(dirname -- "$cur")"
    done
    return 0
}

# Дозволяємо symlink лише як останній компонент джерела.
# Вкладені symlink копіюються як дані, а не розіменовуються.
path_ok_source() {
    local p="${1:-}"
    path_syntax_abs "$p" || return 1
    if [[ -L "$p" ]]; then
        path_ok_abs "$(dirname -- "$p")"
    else
        path_ok_abs "$p"
    fi
}


# Єдиний модуль шляхів. Жоден конфіг не виконується як код.
path_project() { printf '%s/%s' "$ROOT_DIR" "$1"; }
path_dotfiles_root() { path_project dotfiles; }
path_home_relative() { printf '%s/%s' "$HOME" "$1"; }
path_hooks_root() { path_project hooks; }
path_config() { path_project "config/$1"; }
path_hooks() { printf '%s/%s.sh' "$(path_hooks_root)" "$1"; }
path_logs() { path_project logs; }
path_backups() { path_project "backups/$1"; }
path_archives() { path_project archives; }
path_tools() { path_project "tools/$1"; }
path_tests() { path_project "tests/$1"; }

# path_resolve TYPE PATH: заповнює PATH_LIVE, PATH_REPO, PATH_REL.
# TYPE порожній: шлях абсолютний, в репозиторії без префікса.
# TYPE home: тільки ~/ або ${HOME}/, TYPE system: тільки /etc/.
path_resolve() {
    local type="$1" value="$2" relative prefix tilde_prefix
    tilde_prefix="$(printf '%s/' '~')"
    PATH_LIVE='' PATH_REPO='' PATH_REL=''
    case "$type" in
        home)
            case "$value" in
                "$tilde_prefix"*) relative="${value#"$tilde_prefix"}" ;;
                '${HOME}/'*) relative="${value#'${HOME}/'}" ;;
                *) return 2 ;;
            esac
            path_ok_rel "$relative" || return 2
            PATH_LIVE="$HOME/$relative"
            prefix='home/' ;;
        system)
            [[ "$value" == /etc/* ]] || return 2
            path_syntax_abs "$value" || return 2
            relative="${value#/}"
            prefix='system/'
            PATH_LIVE="$value" ;;
        '')
            path_syntax_abs "$value" || return 2
            [[ "$value" != / ]] || return 2
            # Порожній TYPE не може обходити захищений system-режим.
            case "$value" in
                /etc|/etc/*|/root|/root/*|/boot|/boot/*|/usr|/usr/*|/var|/var/*|/bin|/bin/*|/sbin|/sbin/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*)
                    return 2 ;;
            esac
            relative="${value#/}"
            prefix=''
            PATH_LIVE="$value" ;;
        *) return 2 ;;
    esac
    path_ok_rel "$relative" || return 2
    PATH_REL="${prefix}${relative}"
    PATH_REPO="$(path_dotfiles_root)/$PATH_REL"
}

path_repo_sub() { path_project "dotfiles/$1"; }

path_live_for() { path_resolve "$1" "$2" || return 2; printf '%s' "$PATH_LIVE"; }
path_repo_for() { path_resolve "$1" "$2" || return 2; printf '%s' "$PATH_REPO"; }

path_lock_file() { path_project .setup-manager.lock; }
path_restore_temp_pattern() { path_project .restore.XXXXXXXX; }
path_release_tool() { path_tools update_safe.py; }
path_archive_tool() { path_tools archive_safe.py; }
path_recovery_tool() { path_tools recovery_safe.py; }
path_setup_conf() { path_config setup.conf; }
path_package_conf() { path_config packages.conf; }
path_system_backup() { printf '/var/backups/backup-install_manager/system/%s' "$1"; }
