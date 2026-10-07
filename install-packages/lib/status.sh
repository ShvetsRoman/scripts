#!/usr/bin/env bash

# ============================================================
# STATUS ТА VERIFY
# ============================================================
#
# STATUS:
# - інформаційний звіт про поточний стан;
# - показує pacman, AUR, зовнішні пакети, конфіги та сервіси;
# - завжди повертає 0.
#
# VERIFY:
# - строгий контроль очікуваного стану;
# - показує тільки проблеми;
# - повертає 1, якщо знайдено невідповідності.
# ============================================================

print_module_packages_status() {
    local module="$1"
    local array_name package

    array_name="${MODULE_PACMAN_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n packages_ref="$array_name"
        for package in "${packages_ref[@]}"; do
            print_package_status "$package" || true
        done
    fi

    array_name="${MODULE_AUR_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n aur_ref="$array_name"
        for package in "${aur_ref[@]}"; do
            print_package_status "$package" || true
        done
    fi

    array_name="${MODULE_GITHUB_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n github_ref="$array_name"
        for package in "${github_ref[@]}"; do
            print_github_package_status "$package" || true
        done
    fi
}

print_module_services_status() {
    local module="$1"
    local service

    for service in ${MODULE_SERVICES[$module]-}; do
        if service_enabled "$service"; then
            printf '  %-34s %b\n' "$service.service enabled" "${GREEN}YES${NC}"
        else
            printf '  %-34s %b\n' "$service.service enabled" "${YELLOW}NO${NC}"
        fi

        if service_active "$service"; then
            printf '  %-34s %b\n' "$service.service active" "${GREEN}YES${NC}"
        else
            printf '  %-34s %b\n' "$service.service active" "${YELLOW}NO${NC}"
        fi
    done
}

print_module_status() {
    local module="$1"
    local title="${MODULE_TITLES[$module]:-$module}"

    echo
    echo -e "${BOLD}[$title]${NC}"

    print_module_packages_status "$module"

    if [[ -n "${MODULE_CONFIGS[$module]-}" ]]; then
        echo "  Конфігурації:"
        verify_module_configs "$module" || true
    fi

    print_module_services_status "$module"
}

status_modules() {
    local modules=("$@")
    local module

    echo -e "${BOLD}STATUS: поточний стан системи${NC}"

    for module in "${modules[@]}"; do
        print_module_status "$module"
    done

    echo
    log_info "Status завершено. Це інформаційний звіт; стан системи не змінювався."
    return 0
}

verify_package() {
    local package="$1"

    if package_installed "$package"; then
        return 0
    fi

    printf '    %-32s %b\n' "$package" "${RED}MISSING${NC}"
    return 1
}

verify_github_package() {
    local package_id="$1"

    if github_package_installed "$package_id"; then
        return 0
    fi

    printf '    %-32s %b\n' "$package_id" "${RED}MISSING${NC}"
    return 1
}

verify_config() {
    local config_name="$1"
    local parsed module scope source_relative target_value target

    parsed="$(parse_config_mapping "$config_name")" || {
        printf '    %-32s %b\n' "$config_name" "${RED}MAPPING ERROR${NC}"
        return 1
    }

# shellcheck disable=SC2034
    IFS=$'\t' read -r module scope source_relative target_value <<< "$parsed"
    target="$(resolve_config_target "$scope" "$target_value")" || {
        printf '    %-32s %b\n' "$config_name" "${RED}TARGET ERROR${NC}"
        return 1
    }

    if config_matches "$config_name"; then
        return 0
    fi

    local rc=$?
    if ((rc == 2)); then
        printf '    %-20s %-42s %b\n' "$config_name" "$target" "${RED}SOURCE ERROR${NC}"
    elif [[ -e "$target" || -L "$target" ]]; then
        printf '    %-20s %-42s %b\n' "$config_name" "$target" "${RED}CHANGED${NC}"
    else
        printf '    %-20s %-42s %b\n' "$config_name" "$target" "${RED}MISSING${NC}"
    fi

    return 1
}

verify_module_packages() {
    local module="$1"
    local array_name package failed=0

    array_name="${MODULE_PACMAN_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n packages_ref="$array_name"
        for package in "${packages_ref[@]}"; do
            verify_package "$package" || failed=1
        done
    fi

    array_name="${MODULE_AUR_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n aur_ref="$array_name"
        for package in "${aur_ref[@]}"; do
            verify_package "$package" || failed=1
        done
    fi

    array_name="${MODULE_GITHUB_ARRAYS[$module]-}"
    if [[ -n "$array_name" ]]; then
        local -n github_ref="$array_name"
        for package in "${github_ref[@]}"; do
            verify_github_package "$package" || failed=1
        done
    fi

    return "$failed"
}

verify_module_services() {
    local module="$1"
    local service failed=0

    for service in ${MODULE_SERVICES[$module]-}; do
        if ! service_enabled "$service"; then
            printf '    %-32s %b\n' "$service.service enabled" "${RED}NO${NC}"
            failed=1
        fi

        if ! service_active "$service"; then
            printf '    %-32s %b\n' "$service.service active" "${RED}NO${NC}"
            failed=1
        fi
    done

    return "$failed"
}

verify_module() {
    local module="$1"
    local title="${MODULE_TITLES[$module]:-$module}"
    local config_name
    local failed=0

    echo
    echo -e "${BOLD}[$title]${NC}"

    verify_module_packages "$module" || failed=1

    for config_name in ${MODULE_CONFIGS[$module]-}; do
        verify_config "$config_name" || failed=1
    done

    verify_module_services "$module" || failed=1

    if ((failed == 0)); then
        printf '  %b\n' "${GREEN}PASS${NC}"
        return 0
    fi

    printf '  %b\n' "${RED}FAIL${NC}"
    return 1
}

verify_modules() {
    local modules=("$@")
    local module
    local passed=0
    local failed=0

    echo -e "${BOLD}VERIFY: перевірка очікуваного стану${NC}"
    echo "Показуються лише проблеми; модулі без проблем отримують PASS."

    for module in "${modules[@]}"; do
        if verify_module "$module"; then
            ((passed += 1))
        else
            ((failed += 1))
        fi
    done

    echo
    echo -e "${BOLD}Підсумок VERIFY${NC}"
    printf '  Перевірено модулів: %d\n' "${#modules[@]}"
    printf '  Успішно:           %b%d%b\n' "$GREEN" "$passed" "$NC"

    if ((failed > 0)); then
        printf '  З помилками:        %b%d%b\n' "$RED" "$failed" "$NC"
        log_error "Verify завершено: знайдено невідповідності."
        return 1
    fi

    printf '  З помилками:        %b0%b\n' "$GREEN" "$NC"
    log_ok "Verify завершено: система відповідає очікуваному стану."
    return 0
}
