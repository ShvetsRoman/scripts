#!/usr/bin/env bash
# Синхронізація реєстру. Формат: name | mode | src | dst | group.

sync_run() {
    local mode="$1"; shift
    local -a filter=("$@")

    clear 2>/dev/null || true
    sources_load
    ((${#SRC_ROWS[@]})) || { log info 'Реєстр порожній.'; return 0; }

    # Заголовок із назвою операції.
    local title
    case "$mode" in
        backup)   title='↑  backup    HOME → dotfiles' ;;
        restore)  title='↓  restore   dotfiles → HOME' ;;
        *)        title="·  $mode" ;;
    esac
    if ((${#filter[@]})); then
        title+="    [${filter[*]}]"
    fi
    header "$title"

    local row changed=0 skipped=0 failed=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"

        if ((${#filter[@]})); then
            local matched=false f
            for f in "${filter[@]}"; do
                [[ "$S_NAME" == "$f" || "$S_SRC" == "$f" || "$S_DST" == "$f" ]] && matched=true
            done
            $matched || continue
        fi

        local src dst group
        local norm_dst="${S_DST#/}"
        norm_dst="${norm_dst//\/\//\/}"
        if [[ "$mode" == backup ]]; then
            src="$(sources_abs "$S_MODE" "$S_SRC")"
            dst="$ROOT_DIR/dotfiles/$norm_dst"
            group="$S_GROUP"
        else
            src="$ROOT_DIR/dotfiles/$S_DST"
            dst="$(sources_abs "$S_MODE" "$S_SRC")"
            group="recovery"
        fi

        local st=0
        apply "$src" "$dst" "$group" "$S_NAME" || st=$?
        case "$st" in
            0) ((skipped+=1)) ;;
            1) ((changed+=1)) ;;
            *) ((failed+=1)) ;;
        esac
    done

    local summary="оновлено $changed, пропущено $skipped"
    (( failed )) && summary+=", помилок $failed"

    printf '\n'
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

# sync_backup_src — ad-hoc backup у репо.
sync_backup_src() {
    local src="$1" repo_sub="$2"
    path_ok_abs "$src" || { log error "SRC: $src"; return 2; }
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }

    repo_sub="${repo_sub#/}"
    repo_sub="${repo_sub//\/\//\/}"
    local dst="$ROOT_DIR/dotfiles/$repo_sub"

    if [[ "$repo_sub" == */ ]]; then
        mkdir -p -- "$dst" || { log error "Не вдалося створити $dst"; return 2; }
        dst="${dst%/}/$(basename "$src")"
    elif [[ -d "$dst" && -f "$src" ]]; then
        dst="$dst/$(basename "$src")"
    fi

    local st=0
    apply "$src" "$dst" dotfiles "$repo_sub" || st=$?
    return "$st"
}

# sync_restore_src — ad-hoc restore з репо.
sync_restore_src() {
    local repo_sub="$1" target="$2"
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }
    path_ok_abs "$target" || { log error "TARGET: $target"; return 2; }

    repo_sub="${repo_sub#/}"
    repo_sub="${repo_sub//\/\//\/}"
    local src="$ROOT_DIR/dotfiles/$repo_sub"

    if [[ "$target" == */ ]]; then
        mkdir -p -- "$target" || { log error "Не вдалося створити $target"; return 2; }
        target="${target%/}/$(basename "$src")"
    elif [[ -d "$target" ]]; then
        target="$target/$(basename "$src")"
    fi

    local st=0
    apply "$src" "$target" recovery "$repo_sub" || st=$?
    return "$st"
}

sync_status() {
    clear 2>/dev/null || true
    sources_load
    clear 2>/dev/null || true
    header '✦  status    HOME ↔ dotfiles' 
    local status=0 row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        local h r rc
        h="$(sources_abs "$S_MODE" "$S_SRC")"
        local nd="${S_DST#/}"; nd="${nd//\/\//\/}"
        r="$ROOT_DIR/dotfiles/$nd"
        if [[ ! -e "$h" && ! -L "$h" && ! -e "$r" && ! -L "$r" ]]; then
            log warn "[MISSING] $S_NAME"; status=1; continue
        fi
        if [[ ! -e "$h" && ! -L "$h" ]]; then
            log_state DEL "$S_NAME — нема в HOME"; status=1; continue
        fi
        if [[ ! -e "$r" && ! -L "$r" ]]; then
            log_state NEW "$S_NAME — нема в dotfiles"; status=1; continue
        fi
        rc=0
        fs_compare "$h" "$r" || rc=$?
        if (( rc == 0 )); then
            log_state OK "$S_NAME"
        elif (( rc == 1 )); then
            log_state CHANGED "$S_NAME"; status=1
        else
            log error "$S_NAME — помилка порівняння"; status=1
        fi
    done
    return "$status"
}

sync_diff() {
    local -a filter=("$@")
    clear 2>/dev/null || true
    sources_load

    local title='⌥  diff      dotfiles → HOME'
    ((${#filter[@]})) && title+="  [${filter[*]}]"
    header "$title"

    local row total=0 changed=0 missing=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        if ((${#filter[@]})); then
            local matched=false f
            for f in "${filter[@]}"; do
                [[ "$S_NAME" == "$f" || "$S_SRC" == "$f" || "$S_DST" == "$f" ]] && matched=true
            done
            $matched || continue
        fi
        ((total+=1))

        local hp rp out rc
        hp="$(sources_abs "$S_MODE" "$S_SRC")"
        local nd="${S_DST#/}"; nd="${nd//\/\//\/}"
        rp="$ROOT_DIR/dotfiles/$nd"

        if [[ ! -e "$hp" && ! -L "$hp" && ! -e "$rp" && ! -L "$rp" ]]; then
            log warn "[MISSING] $S_NAME"
            ((missing+=1)); continue
        fi

        rc=0
        fs_compare "$hp" "$rp" || rc=$?
        if (( rc == 0 )); then
            continue
        fi
        if (( rc == 2 )); then
            log error "$S_NAME — помилка порівняння"
            continue
        fi
        ((changed+=1))

        if [[ -e "$hp" && -e "$rp" ]]; then
            if command -v git >/dev/null 2>&1; then
                out="$(git --no-pager diff --no-index --color=always -- "$rp" "$hp" 2>&1)" || rc=$?
            elif diff --color=always /dev/null /dev/null >/dev/null 2>&1; then
                out="$(diff --color=always -ruN -- "$rp" "$hp" 2>&1)" || rc=$?
            else
                out="$(diff -ruN -- "$rp" "$hp" 2>&1)" || rc=$?
            fi
            if (( rc > 1 )); then
                log error "diff: $S_NAME"; continue
            fi
            header "Diff: $S_NAME (dotfiles → HOME)"
            if [[ -n "$out" ]]; then
                printf '%s\n' "$out"
            else
                log warn "$S_NAME — метадані різні, вміст однаковий"
            fi
        elif [[ ! -e "$hp" ]]; then
            header "Diff: $S_NAME"
            log warn "$S_NAME — немає в HOME"
        elif [[ ! -e "$rp" ]]; then
            header "Diff: $S_NAME"
            log warn "$S_NAME — немає в dotfiles"
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
