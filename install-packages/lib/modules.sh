#!/usr/bin/env bash

# ============================================================
# ЗАГАЛЬНА ЛОГІКА МОДУЛІВ
# ============================================================
#
# Вся універсальна логіка встановлення читає metadata з
# config/modules.conf. Сам модуль не повинен знати назви
# масивів *_PACKAGES або *_AUR_PACKAGES.
# ============================================================

# Перевіряє, чи оголошено масив з указаним ім'ям.
array_exists() {
    local array_name="$1"
    [[ -n "$array_name" ]] || return 1
    declare -p "$array_name" >/dev/null 2>&1
}

# Встановлює pacman та AUR пакети модуля відповідно до metadata.
install_module_packages() {
    local module="$1"
    local pacman_array="${MODULE_PACMAN_ARRAYS[$module]-}"
    local aur_array="${MODULE_AUR_ARRAYS[$module]-}"

    if [[ -n "$pacman_array" ]]; then
        array_exists "$pacman_array" || {
            log_error "Для модуля '$module' не знайдено масив пакетів: $pacman_array"
            return 1
        }

        local -n pacman_ref="$pacman_array"
        install_pacman "${pacman_ref[@]}"
    fi

    # Порожній mapping означає: AUR-пакетів у модуля немає.
    if [[ -n "$aur_array" ]]; then
        array_exists "$aur_array" || {
            log_error "Для модуля '$module' не знайдено AUR-масив: $aur_array"
            return 1
        }

        local -n aur_ref="$aur_array"
        install_paru "${aur_ref[@]}"
    fi
}

# Увімкнення systemd-сервісів, описаних для модуля.
enable_module_services() {
    local module="$1"
    local service

    for service in ${MODULE_SERVICES[$module]-}; do
        enable_service "$service"
    done
}

# Виконує post-install hook модуля, якщо він заданий.
run_module_post_hook() {
    local module="$1"
    local hook="${MODULE_POST_HOOKS[$module]-}"

    [[ -n "$hook" ]] || return 0

    if ! declare -F "$hook" >/dev/null 2>&1; then
        log_error "Post-install hook '$hook' для модуля '$module' не визначений."
        return 1
    fi

    echo
    log_step "Post-install hook: $hook"
    "$hook"
}

# Стандартна послідовність для будь-якого модуля.
install_registered_module() {
    local module="$1"

    # У --configs-only не встановлюємо пакети, не вмикаємо
    # сервіси й не запускаємо post-install hooks.
    if [[ "$CONFIGS_ONLY" != true ]]; then
        install_module_packages "$module"
    fi

    install_module_configs "$module"

    if [[ "$CONFIGS_ONLY" != true ]]; then
        enable_module_services "$module"
        run_module_post_hook "$module"
    fi
}

# Валідація metadata одного модуля.
validate_module_metadata() {
    local module="$1"
    local dep pacman_array aur_array hook

    [[ -v "MODULE_TITLES[$module]" ]] || {
        log_error "Відсутній MODULE_TITLES[$module]."
        return 1
    }

    [[ -v "MODULE_DEPENDENCIES[$module]" ]] || {
        log_error "Відсутній MODULE_DEPENDENCIES[$module]."
        return 1
    }

    [[ -v "MODULE_PACMAN_ARRAYS[$module]" ]] || {
        log_error "Відсутній MODULE_PACMAN_ARRAYS[$module]."
        return 1
    }

    [[ -v "MODULE_AUR_ARRAYS[$module]" ]] || {
        log_error "Відсутній MODULE_AUR_ARRAYS[$module]."
        return 1
    }

    [[ -v "MODULE_SERVICES[$module]" ]] || {
        log_error "Відсутній MODULE_SERVICES[$module]."
        return 1
    }

    [[ -v "MODULE_POST_HOOKS[$module]" ]] || {
        log_error "Відсутній MODULE_POST_HOOKS[$module]."
        return 1
    }

    [[ -v "MODULE_CONFIGS[$module]" ]] || {
        log_error "Відсутній MODULE_CONFIGS[$module]."
        return 1
    }

    for dep in ${MODULE_DEPENDENCIES[$module]-}; do
        module_exists "$dep" || {
            log_error "Модуль '$module' залежить від невідомого модуля '$dep'."
            return 1
        }
    done

    pacman_array="${MODULE_PACMAN_ARRAYS[$module]-}"
    if [[ -n "$pacman_array" ]] && ! array_exists "$pacman_array"; then
        log_error "Модуль '$module': не знайдено масив '$pacman_array' у packages.conf."
        return 1
    fi

    aur_array="${MODULE_AUR_ARRAYS[$module]-}"
    if [[ -n "$aur_array" ]] && ! array_exists "$aur_array"; then
        log_error "Модуль '$module': не знайдено AUR-масив '$aur_array' у packages.conf."
        return 1
    fi

    hook="${MODULE_POST_HOOKS[$module]-}"
    if [[ -n "$hook" && ! "$hook" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_error "Модуль '$module': некоректне ім'я hook '$hook'."
        return 1
    fi
}
