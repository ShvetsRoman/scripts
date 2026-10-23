#!/usr/bin/env bash
# Recovery V2: перевірка manifest.tsv, SHA-256 та безпечне відновлення.
recovery_dir() { path_backups recovery; }

recovery_valid_id() {
    [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9]+(_[0-9]+)?$ ]]
}

recovery_list() {
    ui_clear
    header '♻  recovery list'
    local dir; dir="$(recovery_dir)"
    [[ -d "$dir" ]] || { log info 'Recovery-копій немає.'; return 0; }
    local -a snaps=()
    mapfile -t snaps < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    ((${#snaps[@]})) || { log info 'Recovery-копій немає.'; return 0; }
    printf '%s\n' "${snaps[@]}"
}

# Читає та перевіряє ВСІ рядки manifest до будь-яких змін.
# В результаті заповнює RECOVERY_RELS і RECOVERY_TARGETS.
recovery_load_manifest() {
    local snapshot="$1"
    local manifest="$snapshot/manifest.tsv"
    local rel target old
    RECOVERY_RELS=() RECOVERY_TARGETS=()
    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        log error 'Recovery без manifest.tsv: старі знімки відновлюються тільки вручну'; return 2;
    }
    local -A seen=()
    while IFS=$'\t' read -r rel target || [[ -n "$rel" || -n "$target" ]]; do
        [[ -n "$rel" && -n "$target" ]] && path_ok_rel "$rel" && path_ok_abs "$target" || {
            log error 'Некоректний або небезпечний рядок manifest'; return 2;
        }
        [[ -z "${seen[$rel]:-}" ]] || { log error 'Дублікат у manifest'; return 2; }
        for old in "${RECOVERY_TARGETS[@]}"; do
            [[ "$old" != "$target" && "$old" != "$target/"* && "$target" != "$old/"* ]] || {
                log error "Конфлікт шляхів відновлення: $target"; return 2;
            }
        done
        [[ -e "$snapshot/data/$rel" || -L "$snapshot/data/$rel" ]] && \
            path_ok_source "$snapshot/data/$rel" || {
            log error "Немає безпечних даних: $rel"; return 2;
        }
        seen[$rel]=1
        RECOVERY_RELS+=("$rel") RECOVERY_TARGETS+=("$target")
        ((${#RECOVERY_RELS[@]} <= 1000)) || { log error 'Забагато записів у manifest'; return 2; }
    done < "$manifest"
    ((${#RECOVERY_RELS[@]})) || { log error 'Порожній manifest'; return 2; }
}

# 0 = SHA-256 підтверджено; 3 = legacy без контрольних сум;
# 1/2 = пошкоджено або небезпечний manifest.
recovery_verify() {
    local id="${1:-}" snapshot helper rc=0
    recovery_valid_id "$id" || { log error "ID: $id"; return 2; }
    snapshot="$(recovery_dir)/$id"
    [[ -d "$snapshot" && ! -L "$snapshot" ]] && path_ok_abs "$snapshot" || {
        log error "Немає безпечного recovery: $id"; return 2;
    }
    recovery_load_manifest "$snapshot" || return 2
    helper="$(path_recovery_tool)"
    recovery_helper_run "$helper" verify "$snapshot" || rc=$?
    return "$rc"
}

# Перевірити список вибраних записів після повної integrity-перевірки.
recovery_selection_check() {
    local requested rel found
    for requested in "$@"; do
        found=false
        for rel in "${RECOVERY_RELS[@]}"; do
            [[ "$requested" == "$rel" ]] && { found=true; break; }
        done
        if [[ "$found" == false ]]; then
            log error "Немає у recovery: $requested"
            return 2
        fi
    done
}

recovery_entry_selected() {
    local rel="$1" selected; shift
    (($# == 0)) && return 0
    for selected in "$@"; do [[ "$rel" == "$selected" ]] && return 0; done
    return 1
}

# План показує лише вибрані об'єкти й ніколи не змінює файли.
recovery_plan() {
    local id="${1:-}" rc=0 i total=0; (($#)) && shift
    recovery_verify "$id" || rc=$?
    [[ "$rc" == 0 || "$rc" == 3 ]] || return "$rc"
    recovery_selection_check "$@" || return 2
    header "Recovery plan: $id"
    for i in "${!RECOVERY_RELS[@]}"; do
        recovery_entry_selected "${RECOVERY_RELS[i]}" "$@" || continue
        printf 'RESTORE %s -> %s\n' "${RECOVERY_RELS[i]}" "${RECOVERY_TARGETS[i]}"
        ((total+=1))
    done
    log info "Об'єктів для відновлення: $total"
}

recovery_restore() {
    ui_clear
    header '♻  recovery restore'
    local id="${1:-}" src rc=0 i failures=0 changed=0 skipped=0 selected=0
    (($#)) && shift
    recovery_verify "$id" || rc=$?
    case "$rc" in
        0) ;;
        3) log warn 'Це старий recovery без SHA-256: перевірити вміст неможливо' ;;
        *) log error 'Відновлення скасовано: integrity check не пройдено'; return "$rc" ;;
    esac
    recovery_selection_check "$@" || return 2
    for i in "${!RECOVERY_RELS[@]}"; do
        if recovery_entry_selected "${RECOVERY_RELS[i]}" "$@"; then ((selected+=1)); fi
    done
    src="$(recovery_dir)/$id"
    if [[ "${DRY_RUN:-false}" != true ]]; then
        setup_confirm "Відновити $id ($selected об'єктів)?" || return 0
    fi
    for i in "${!RECOVERY_RELS[@]}"; do
        recovery_entry_selected "${RECOVERY_RELS[i]}" "$@" || continue
        if apply "$src/data/${RECOVERY_RELS[i]}" "${RECOVERY_TARGETS[i]}" recovery "${RECOVERY_RELS[i]}"; then
            case "$APPLY_RESULT" in
                changed) ((changed+=1)) ;;
                *) ((skipped+=1)) ;;
            esac
        else
            ((failures+=1))
        fi
    done
    printf '\n'
    if (( failures )); then
        log error "Recovery $id: змінено $changed, пропущено $skipped, помилок $failures"
        return 1
    fi
    log ok "Recovery $id: змінено $changed, пропущено $skipped, помилок 0"
}

recovery_delete() {
    ui_clear
    header '♻  recovery delete'
    local id="${1:-}" dir
    recovery_valid_id "$id" || return 2
    dir="$(recovery_dir)/$id"
    [[ -d "$dir" && ! -L "$dir" ]] && path_ok_abs "$dir" || return 1
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] rm $dir"; return 0; }
    setup_confirm "Видалити $id?" || return 0
    rm -rf -- "$dir"
}

recovery_main() {
    case "${1:-list}" in
        list) recovery_list ;;
        verify) [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; recovery_verify "$2" ;;
        plan) [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; shift; recovery_plan "$@" ;;
        restore) [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; shift; recovery_restore "$@" ;;
        delete) [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; recovery_delete "$2" ;;
        *) log error 'recovery list|verify ID|plan ID [REL...]|restore ID [REL...]|delete ID'; return 2 ;;
    esac
}
