#!/usr/bin/env bash
doctor_main() {
    local command errors=0 warnings=0 count=0
    print_header "Setup Manager $SETUP_VERSION: Doctor"
    for command in bash rsync tar git diff cmp find flock pacman sudo python3; do
        if command -v "$command" >/dev/null; then log_ok "$command"; else log_error "Не знайдено: $command"; ((errors+=1)); fi
    done
    if command -v paru >/dev/null; then log_ok 'paru (AUR)'; else log_warn 'paru відсутній'; ((warnings+=1)); fi
    while IFS= read -r _; do ((count+=1)); done < <(registry_ids)
    printf '\nПідсумок: модулів %s, помилок %s, попереджень %s\n' "$count" "$errors" "$warnings"
    (( errors==0 ))
}
smart_main() {
    local -a args=("$@")
    print_header 'SMART SETUP'
    doctor_main || { log_error 'Doctor не пройдено'; return 1; }
    log_info 'Smart Setup встановлює програми та застосовує їхні конфігурації.'
    log_info 'Backup та Restore dotfiles виконуються окремо.'
    if ((${#args[@]}==0)); then args=(--dry-run all); fi
    packages_main "${args[@]}"
}
