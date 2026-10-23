#!/usr/bin/env bash
# Кожен hook запускається в окремому процесі через спільний runtime.
# Самі шляхи обчислюються лише в src/core/path.sh.
_hooks_exec() {
    local file="$1"
    SETUP_ROOT="$ROOT_DIR" \
    SETUP_DRY_RUN="${DRY_RUN:-false}" \
    SETUP_LOG_FILE="${SETUP_LOG_FILE:-}" \
    SETUP_RUN_ID="${SETUP_RUN_ID:-}" \
    SETUP_COLOR="${SETUP_COLOR:-auto}" \
    SETUP_TEST_MODE="${SETUP_TEST_MODE:-false}" \
    SETUP_NO_CLEAR="${SETUP_NO_CLEAR:-false}" \
    bash "$(path_project src/hooks/hook_runtime.sh)" "$file"
}

hooks_validate() {
    local id="$1" name file
    local -a names=()
    read -r -a names <<< "${PACKAGE_HOOKS[$id]:-}"
    # Каталог hooks не може бути символічним посиланням.
    [[ -d "$(path_project hooks)" && ! -L "$(path_project hooks)" ]] || {
        log error "Каталог hooks відсутній або є посиланням: $(path_project hooks)"
        return 2
    }
    local binding
    for binding in "${!PACKAGE_BOUND_HOOKS[@]}"; do
        if [[ "$binding" == "$id|"* ]]; then
            names+=("${PACKAGE_BOUND_HOOKS[$binding]}")
        fi
    done
    for name in "${names[@]}"; do
        [[ "$name" =~ ^[a-z][a-z0-9_-]*$ ]] || { log error "Некоректний hook: $name"; return 2; }
        file="$(path_hooks "$name")"
        [[ -f "$file" && ! -L "$file" ]] || { log error "Hook відсутній: $file"; return 2; }
        bash -n "$file" || { log error "Синтаксис hook: $file"; return 2; }
    done
    return 0
}
hooks_run() {
    local id="$1" name file rc
    local -a names=()
    hooks_validate "$id" || return 2
    read -r -a names <<< "${PACKAGE_HOOKS[$id]:-}"
    for name in "${names[@]}"; do
        file="$(path_hooks "$name")"
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log info "[DRY-RUN] bash hooks/$name.sh"
            continue
        fi
        log step "Загальний hook $name"
        if _hooks_exec "$file"; then
            log ok "Загальний hook $name виконано"
        else
            rc=$?
            log error "Hook $name завершився з кодом $rc"
            return "$rc"
        fi
    done
    return 0
}

# Прив'язаний hook виконується після успішного встановлення пакета.
hooks_run_bound() {
    local name package file rc
    name="$1"
    package="$2"
    file="$(path_hooks "$name")"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] Hook $name для пакета $package"
        return 0
    fi
    log step "Hook $name для пакета $package"
    if _hooks_exec "$file"; then
        log ok "Hook $name для пакета $package виконано"
    else
        rc=$?
        log error "Hook $name для пакета $package: код $rc"
        return "$rc"
    fi
}
