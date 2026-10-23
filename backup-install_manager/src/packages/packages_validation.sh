#!/usr/bin/env bash
# Єдина міжреєстрова перевірка packages.conf та dotfiles.conf.
# Накопичує всі помилки посилань і конфліктів, не перериваючи перевірку груп.
packages_validate_references() {
    local id item row bound group package previous
    local errors=0
    # Результат читається Doctor з іншого модуля.
    # shellcheck disable=SC2034
    PACKAGES_VALIDATION_ERRORS=0
    local -A known_configs=() seen_packages=() known_groups=() used_configs=()
    local -a items=()

    # Реєстр dotfiles уже пройшов перевірку формату.
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row" || return 2
        known_configs["$S_NAME"]=1
    done
    for group in "${DOTFILES_GROUPS[@]}"; do known_groups["$group"]=1; done

    for id in "${PACKAGE_IDS[@]}"; do
        group="${PACKAGE_CONFIGS_GROUP[$id]:-}"
        used_configs=()
        if [[ -n "$group" ]]; then
            if [[ ! -v known_groups["$group"] ]]; then
                log error "packages.conf: $id.configs_group: невідома група $group (рядок ${PACKAGE_FIELD_LINES["$id.configs_group"]:-?})"
                errors=$((errors + 1))
            else
                for item in "${!DOTFILES_ITEM_GROUP[@]}"; do
                    if [[ "${DOTFILES_ITEM_GROUP[$item]}" == "$group" ]]; then
                        used_configs["$item"]="configs_group"
                    fi
                done
            fi
        fi

        read -r -a items <<< "${PACKAGE_CONFIGS[$id]:-}"
        for item in "${items[@]}"; do
            if [[ ! -v known_configs["$item"] ]]; then
                log error "packages.conf: $id.configs: невідомий запис $item (рядок ${PACKAGE_FIELD_LINES["$id.configs"]:-?})"
                errors=$((errors + 1))
            fi
            if [[ -v used_configs["$item"] ]]; then
                previous="${used_configs[$item]}"
                log error "packages.conf: $id: конфіг $item повторено ($previous та configs) (рядок ${PACKAGE_FIELD_LINES["$id.configs"]:-?})"
                errors=$((errors + 1))
            else
                used_configs["$item"]="configs"
            fi
        done

        # Сортування забезпечує стабільний порядок діагностики прив'язаних полів.
        local -a bounds=()
        for bound in "${!PACKAGE_BOUND_CONFIGS[@]}"; do
            [[ "$bound" == "$id|"* ]] && bounds+=("$bound")
        done
        if ((${#bounds[@]})); then
            mapfile -t bounds < <(printf '%s\n' "${bounds[@]}" | LC_ALL=C sort)
        fi
        for bound in "${bounds[@]}"; do
            package="${bound#*|}"
            read -r -a items <<< "${PACKAGE_BOUND_CONFIGS[$bound]}"
            for item in "${items[@]}"; do
                if [[ ! -v known_configs["$item"] ]]; then
                    log error "packages.conf: $id.config.$package: невідомий запис $item (рядок ${PACKAGE_FIELD_LINES["$id.config.$package"]:-?})"
                    errors=$((errors + 1))
                fi
                if [[ -v used_configs["$item"] ]]; then
                    previous="${used_configs[$item]}"
                    log error "packages.conf: $id: конфіг $item повторено ($previous та config.$package) (рядок ${PACKAGE_FIELD_LINES["$id.config.$package"]:-?})"
                    errors=$((errors + 1))
                else
                    used_configs["$item"]="config.$package"
                fi
            done
        done

        seen_packages=()
        read -r -a items <<< "${PACKAGE_PACMAN[$id]:-}"
        for item in "${items[@]}"; do seen_packages["$item"]=1; done
        read -r -a items <<< "${PACKAGE_AUR[$id]:-}"
        for item in "${items[@]}"; do
            if [[ -v seen_packages["$item"] ]]; then
                log error "packages.conf: $id: пакет $item одночасно в pacman і aur (рядки ${PACKAGE_FIELD_LINES["$id.pacman"]:-?}, ${PACKAGE_FIELD_LINES["$id.aur"]:-?})"
                errors=$((errors + 1))
            fi
        done
    done
    # shellcheck disable=SC2034
    PACKAGES_VALIDATION_ERRORS="$errors"
    if ((errors > 0)); then
        log error "packages.conf: знайдено помилок: $errors"
        return 2
    fi
    log ok 'packages.conf: configs та джерела пакетів перевірено'
}
