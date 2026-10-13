#!/usr/bin/env bash
# Діагностика.

# doctor_main — перевіряє наявність потрібних команд.
# Повертає 0, якщо немає критичних помилок.
doctor_main() {
    header "Doctor — Setup Manager $SETUP_VERSION"
    local errors=0 warnings=0 count=0 cmd
    for cmd in bash rsync tar diff cmp find flock pacman sudo python3; do
        if command -v "$cmd" >/dev/null; then log ok "$cmd"; else log error "Немає: $cmd"; errors=$((errors+1)); fi
    done
    if command -v paru >/dev/null; then log ok 'paru'; else log warn 'paru відсутній'; warnings=$((warnings+1)); fi
    while IFS= read -r _; do count=$((count+1)); done < <(registry_ids)
    printf '\nМодулів: %s, помилок: %s, попереджень: %s\n' "$count" "$errors" "$warnings"
    (( errors == 0 ))
}

# smart_main — швидкий старт: doctor + встановити все у dry-run.
smart_main() {
    header 'SMART SETUP'
    doctor_main || { log error 'Doctor не пройдено'; return 1; }
    log info 'Smart Setup: програми + конфіги.'
    local -a args=("$@")
    ((${#args[@]})) || args=(--dry-run all)
    packages_main "${args[@]}"
}
