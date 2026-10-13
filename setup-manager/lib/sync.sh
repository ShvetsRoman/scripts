#!/usr/bin/env bash
# Синхронізація реєстру.

# sync_run — цикл по реєстру у напрямку backup|restore.
# Аргументи: $1 — mode; далі — фільтр (порожньо = усі).
# Повертає 1, якщо були помилки.
sync_run() {
    local mode="$1"; shift
    local -a filter=("$@")

    sources_load
    ((${#SRC_ROWS[@]})) || { log info 'Реєстр порожній.'; return 0; }

    local row changed=0 skipped=0 failed=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"

        if ((${#filter[@]})); then
            local matched=false f
            for f in "${filter[@]}"; do
                [[ "$S_SRC" == "$f" || "$S_DST" == "$f" ]] && matched=true
            done
            $matched || continue
        fi

        local src dst group
        if [[ "$mode" == backup ]]; then
            src="$(sources_abs "$S_MODE" "$S_SRC")"
            dst="$ROOT_DIR/dotfiles/$S_DST"
            group="$S_GROUP"
        else
            src="$ROOT_DIR/dotfiles/$S_DST"
            dst="$(sources_abs "$S_MODE" "$S_SRC")"
            group="recovery"
        fi

        local st=0
        apply "$src" "$dst" "$group" "$S_DST" || st=$?
        case "$st" in
            0) ((skipped+=1)) ;;
            1) ((changed+=1)) ;;
            *) ((failed+=1)) ;;
        esac
    done

    local summary="оновлено $changed, пропущено $skipped"
    (( failed )) && summary+=", помилок $failed"
    if (( failed )); then
        log error "$mode: $summary"
        return 1
    fi
    if (( changed == 0 && skipped > 0 )); then
        log info "$mode: нічого не змінилось ($summary)"
    else
        log ok "$mode: $summary"
    fi
}

# sync_backup_src — ad-hoc backup з довільного місця.
# Аргументи: SRC (абс), REPO_SUB (відносний).
sync_backup_src() {
    local src="$1" repo_sub="$2"
    path_ok_abs "$src" || { log error "SRC: $src"; return 2; }
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }
    local st=0
    apply "$src" "$ROOT_DIR/dotfiles/$repo_sub" dotfiles "$repo_sub" || st=$?
    return "$st"
}

# sync_restore_src — ad-hoc restore з репо у довільне місце.
# Аргументи: REPO_SUB (відносний), TARGET (абс).
sync_restore_src() {
    local repo_sub="$1" target="$2"
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }
    path_ok_abs "$target" || { log error "TARGET: $target"; return 2; }
    local st=0
    apply "$ROOT_DIR/dotfiles/$repo_sub" "$target" recovery "$repo_sub" || st=$?
    return "$st"
}

# sync_status — стан реєстру: OK / CHANGED / NEW / DEL / MISSING.
# Повертає 1, якщо є хоч одне відхилення.
sync_status() {
    sources_load
    header 'Status — реєстр'
    local status=0 row h r rc
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        h="$(sources_abs "$S_MODE" "$S_SRC")"
        r="$ROOT_DIR/dotfiles/$S_DST"

        if [[ ! -e "$h" && ! -L "$h" && ! -e "$r" && ! -L "$r" ]]; then
            log warn "[MISSING] $S_DST"
            status=1
            continue
        fi
        if [[ ! -e "$h" && ! -L "$h" ]]; then
            log_state DEL "$S_DST — нема в HOME"
            status=1
            continue
        fi
        if [[ ! -e "$r" && ! -L "$r" ]]; then
            log_state NEW "$S_DST — нема в dotfiles"
            status=1
            continue
        fi

        rc=0
        fs_compare "$h" "$r" || rc=$?
        if (( rc == 0 )); then
            log_state OK "$S_DST"
        elif (( rc == 1 )); then
            log_state CHANGED "$S_DST"
            status=1
        else
            log error "$S_DST — помилка порівняння"
            status=1
        fi
    done
    return "$status"
}

# sync_diff — показує різниці між HOME і dotfiles.
# Аргументи: фільтр (порожньо = усі).
# Повертає 0, якщо все синхронізовано; 1, якщо є різниці.
sync_diff() {
    local -a filter=("$@")
    sources_load
    local row total=0 changed=0 missing=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"

        if ((${#filter[@]})); then
            local matched=false f
            for f in "${filter[@]}"; do
                [[ "$S_SRC" == "$f" || "$S_DST" == "$f" ]] && matched=true
            done
            $matched || continue
        fi
        ((total+=1))

        local hp rp out rc
        hp="$(sources_abs "$S_MODE" "$S_SRC")"
        rp="$ROOT_DIR/dotfiles/$S_DST"

        if [[ ! -e "$hp" && ! -L "$hp" && ! -e "$rp" && ! -L "$rp" ]]; then
            log warn "[MISSING] $S_DST"
            ((missing+=1))
            continue
        fi

        rc=0
        fs_compare "$hp" "$rp" || rc=$?

        if (( rc == 0 )); then
            continue
        fi
        if (( rc == 2 )); then
            log error "$S_DST — помилка порівняння"
            continue
        fi

        ((changed+=1))

        if [[ -e "$hp" && -e "$rp" ]]; then
            out="$(diff --color=always -ruN -- "$rp" "$hp" 2>&1)" || rc=$?
            if (( rc > 1 )); then
                log error "diff: $S_DST"
                continue
            fi
            header "Diff: $S_DST (dotfiles → HOME)"
            if [[ -n "$out" ]]; then
                printf '%s\n' "$out"
            else
                log warn "$S_DST — метадані різні, вміст однаковий"
            fi
        elif [[ ! -e "$hp" ]]; then
            header "Diff: $S_DST"
            log warn "$S_DST — немає в HOME"
        elif [[ ! -e "$rp" ]]; then
            header "Diff: $S_DST"
            log warn "$S_DST — немає в dotfiles"
        fi
    done

    if (( changed == 0 && missing == 0 )); then
        printf '\n'
        log ok "Diff: усе синхронізовано ($total)"
        return 0
    fi
    printf '\n'
    log warn "Diff: відрізняються $changed, відсутні $missing (з $total)"
    return 1
}
