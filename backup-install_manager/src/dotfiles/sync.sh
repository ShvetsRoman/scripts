#!/usr/bin/env bash
# Синхронізація реєстру. Формат: ID | TYPE | PATH.

sync_run() {
    local mode="$1"; shift
    local changed_only=false
    if [[ "${1:-}" == --changed ]]; then
        changed_only=true
        shift
    fi
    local -a filter=("$@")

    ui_clear
    sources_load || return 2
    ((${#SRC_ROWS[@]})) || { log info 'Реєстр порожній.'; return 0; }

    # Невідомі фільтри — помилка, а не хибний успіх без дій.
    local filter_item known check_row
    for filter_item in "${filter[@]}"; do
        known=false
        for check_row in "${SRC_ROWS[@]}"; do
            sources_parse "$check_row"
            if [[ "$filter_item" == "$S_NAME" || "$filter_item" == "$S_SRC" || "$filter_item" == "$S_REPO_REL" ]]; then
                known=true; break
            fi
        done
        if [[ "$known" == false ]]; then
            log error "Немає шляху в реєстрі: $filter_item"
            return 2
        fi
    done

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

    fs_guard_delete || return 2
    local row changed=0 unchanged=0 missing=0 failed=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"

        if ((${#filter[@]})); then
            local matched=false f
            for f in "${filter[@]}"; do
                [[ "$S_NAME" == "$f" || "$S_SRC" == "$f" || "$S_REPO_REL" == "$f" ]] && matched=true
            done
            $matched || continue
        fi

        local src dst group
        if [[ "$mode" == backup ]]; then
            src="$(path_live_for "$S_MODE" "$S_SRC")"
            dst="$(path_repo_for "$S_MODE" "$S_SRC")"
            group="dotfiles"
        else
            src="$(path_repo_for "$S_MODE" "$S_SRC")"
            dst="$(path_live_for "$S_MODE" "$S_SRC")"
            group="recovery"
        fi

        # Backup Changed не торкається записів без змін і не створює
        # для них захисних копій. Зміни визначаються за вмістом (rsync -c).
        # Без --sync-delete зайві файли в dotfiles не є зміною.
        if [[ "$changed_only" == true ]]; then
            if [[ ! -e "$src" && ! -L "$src" ]]; then
                log warn "[MISSING] $S_NAME: $src"
                ((missing+=1))
                continue
            fi
            if ! path_ok_source "$src" || ! path_ok_abs "$dst"; then
                log error "$S_NAME — небезпечний шлях"
                ((failed+=1))
                continue
            fi
            local cmp_rc=0
            if [[ "${SYNC_DELETE:-false}" == true ]]; then
                fs_compare "$src" "$dst" || cmp_rc=$?
            else
                fs_compare_copy "$src" "$dst" || cmp_rc=$?
            fi
            case "$cmp_rc" in
                0) log_state SKIP "$S_NAME — без змін"; ((unchanged+=1)); continue ;;
                1) ;; # Є відмінності — передаємо apply(), який знову перевірить безпеку.
                *) log error "$S_NAME — неможливо порівняти"; ((failed+=1)); continue ;;
            esac
        fi

        if [[ "$mode" == restore && "$S_MODE" == system ]]; then
            # system mode is intentionally restricted to registered files in /etc.
            if system_restore "$src" "$dst" "$S_NAME"; then
                rc=0
            else
                rc=$?
            fi
        elif apply "$src" "$dst" "$group" "$S_NAME"; then
            rc=0
        else
            rc=$?
        fi
        if (( rc == 0 )); then
            case "$APPLY_RESULT" in
                changed) ((changed+=1)) ;;
                unchanged) ((unchanged+=1)) ;;
                *) ((missing+=1)) ;;
            esac
        else
            ((failed+=1))
        fi
    done

    local summary="оновлено $changed, без змін $unchanged, відсутніх $missing, помилок $failed"

    printf '\n'
    if (( failed )); then
        log error "$mode: $summary"
        return 1
    fi
    if (( changed == 0 && unchanged > 0 && missing == 0 )); then
        log info "$mode: нічого не змінилось ($summary)"
    else
        log ok "$mode: $summary"
    fi
}

# sync_backup_src — ad-hoc backup у репо.
sync_backup_src() {
    local src="$1" repo_sub="$2" dst
    path_ok_abs "$src" || { log error "SRC: $src"; return 2; }
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }
    dst="$(path_repo_sub "$repo_sub")"
    if [[ "$repo_sub" == */ ]]; then
        dst="${dst%/}/$(basename -- "$src")"
    elif [[ -d "$dst" && -f "$src" ]]; then
        dst="$dst/$(basename -- "$src")"
    fi
    apply "$src" "$dst" dotfiles "$repo_sub"
}

sync_restore_src() {
    local repo_sub="$1" target="$2" src
    path_ok_rel "$repo_sub" || { log error "REPO_SUB: $repo_sub"; return 2; }
    path_ok_abs "$target" || { log error "TARGET: $target"; return 2; }
    src="$(path_repo_sub "$repo_sub")"
    if [[ "$target" == */ ]]; then
        target="${target%/}/$(basename -- "$src")"
    elif [[ -d "$target" ]]; then
        target="$target/$(basename -- "$src")"
    fi
    apply "$src" "$target" recovery "$repo_sub"
}

# Для каталогу показуємо саме відсутні файли/підкаталоги.
# HOME-only => NEW (потрібен backup), dotfiles-only => DEL (потрібен restore).
# Не виводимо всі вкладені елементи, якщо відсутній цілий підкаталог.
sync_report_missing_side() {
    local from="$1" to="$2" state="$3" name="$4" count_var="${5:-}"
    local path rel parent known note
    case "$state" in
        NEW) note='є в HOME, немає в dotfiles' ;;
        DEL) note='є в dotfiles, немає в HOME' ;;
        *)   note='відсутній на іншому боці' ;;
    esac
    local -a missing_dirs=()
    [[ -d "$from" && -d "$to" ]] || return 0
    while IFS= read -r -d '' path; do
        rel="${path#"$from"/}"
        [[ -e "$to/$rel" || -L "$to/$rel" ]] && continue
        known=false
        for parent in "${missing_dirs[@]}"; do
            if [[ "$rel" == "$parent/"* ]]; then
                known=true; break
            fi
        done
        [[ "$known" == true ]] && continue
        if [[ -d "$path" ]]; then
            missing_dirs+=("$rel")
            log_state "$state" "$name/$rel/ — $note"
        else
            log_state "$state" "$name/$rel — $note"
        fi
        # У status/diff/verify лічильники можуть бути локальними у викликача.
        # Bash nameref оновлює саме цей лічильник, без subshell чи втрати значення.
        if [[ -n "$count_var" ]]; then
            local -n count_ref="$count_var"
            ((count_ref+=1))
        fi
    done < <(find -P "$from" -mindepth 1 -print0)
}

sync_report_nested_missing() {
    local home="$1" repo="$2" name="$3"
    local new_count="${4:-}" del_count="${5:-}"
    [[ -d "$home" && -d "$repo" ]] || return 0
    sync_report_missing_side "$home" "$repo" NEW "$name" "$new_count"
    sync_report_missing_side "$repo" "$home" DEL "$name" "$del_count"
}

# Елементи поза dotfiles.conf не мають однозначного шляху в HOME:
# показуємо їх як UNTRACKED, а не приписуємо хибний шлях призначення.
sync_report_untracked() {
    local count_var="${1:-}"
    local path rel row tracked parent
    local -a paths=() untracked_dirs=()
    local dotroot
    dotroot="$(path_dotfiles_root)"
    [[ -d "$dotroot" ]] || return 0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        paths+=("$S_REPO_REL")
    done
    while IFS= read -r -d '' path; do
        rel="${path#"$dotroot"/}"
        case "$rel" in
            .git|.git/*|.gitkeep|*/.gitkeep) continue ;;
        esac
        tracked=false
        for parent in "${paths[@]}"; do
            if [[ "$rel" == "$parent" || "$rel" == "$parent/"* || "$parent" == "$rel/"* ]]; then
                tracked=true; break
            fi
        done
        [[ "$tracked" == true ]] && continue
        for parent in "${untracked_dirs[@]}"; do
            if [[ "$rel" == "$parent/"* ]]; then
                tracked=true; break
            fi
        done
        [[ "$tracked" == true ]] && continue
        [[ -d "$path" ]] && untracked_dirs+=("$rel")
        log_state UNTRACKED "$rel — є в dotfiles, немає запису в dotfiles.conf"
        if [[ -n "$count_var" ]]; then
            local -n count_ref="$count_var"
            ((count_ref+=1))
        fi
    done < <(find -P "$dotroot" -mindepth 1 -print0)
}

# Єдина класифікація пари шляхів. Не друкує повідомлень і не змінює файлів.
# Стани: MISSING, SOURCE_ONLY, TARGET_ONLY, UNSAFE, SAME, CHANGED, ERROR.
# У режимі copy порівняння не враховує зайві файли в призначенні.
sync_classify() {
    local source="$1" target="$2" mode="${3:-full}" rc=0
    SYNC_CLASS=ERROR
    if [[ ! -e "$source" && ! -L "$source" ]]; then
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            SYNC_CLASS=MISSING
        else
            SYNC_CLASS=TARGET_ONLY
        fi
        return 0
    fi
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        SYNC_CLASS=SOURCE_ONLY
        return 0
    fi
    if ! path_ok_source "$source" || ! path_ok_source "$target"; then
        SYNC_CLASS=UNSAFE
        return 0
    fi
    if [[ "$mode" == copy ]]; then
        fs_compare_copy "$source" "$target" || rc=$?
    else
        fs_compare "$source" "$target" || rc=$?
    fi
    case "$rc" in
        0) SYNC_CLASS=SAME ;;
        1) SYNC_CLASS=CHANGED ;;
        *) SYNC_CLASS=ERROR ;;
    esac
    return 0
}

# Відмінність або відсутність — це стан, не помилка: код 0.
# Код 2 — некоректний запит / неможливе порівняння.
sync_status() {
    local -a filters=("$@")
    sources_load || return 2
    sync_validate_filter "${filters[@]}" || return 2
    header '✦  status    HOME ↔ dotfiles'
    local row home repo failed=0 equal=0 changed=0 only_home=0 only_repo=0 missing=0 untracked=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        sync_row_selected "${filters[@]}" || continue
        home="$(path_live_for "$S_MODE" "$S_SRC")"
        repo="$(path_repo_for "$S_MODE" "$S_SRC")"
        sync_classify "$home" "$repo"
        case "$SYNC_CLASS" in
            MISSING) log_state MISSING "$S_NAME — немає ні в HOME, ні в dotfiles"; ((missing+=1)) ;;
            TARGET_ONLY) log_state DEL "$S_NAME — є в dotfiles, немає в HOME"; ((only_repo+=1)) ;;
            SOURCE_ONLY) log_state NEW "$S_NAME — є в HOME, немає в dotfiles"; ((only_home+=1)) ;;
            UNSAFE) log error "$S_NAME — небезпечний шлях"; ((failed+=1)) ;;
            SAME) log_state OK "$S_NAME"; ((equal+=1)) ;;
            CHANGED)
                log_state CHANGED "$S_NAME — є відмінності між HOME і dotfiles"
                ((changed+=1))
                sync_report_nested_missing "$home" "$repo" "$S_NAME" only_home only_repo ;;
            ERROR) log error "$S_NAME — помилка порівняння"; ((failed+=1)) ;;
        esac
    done
    if ((${#filters[@]} == 0)); then
        sync_report_untracked untracked
    fi
    printf '\n'
    log info "Status: однакових $equal, змінених $changed, тільки в HOME $only_home, тільки в dotfiles $only_repo, відсутніх $missing, поза реєстром $untracked, помилок $failed"
    ((failed == 0)) || return 2
    return 0
}

sync_diff() {
    local -a filter=("$@")
    ui_clear
    sources_load || return 2
    sync_validate_filter "${filter[@]}" || return 2
    local title='⌥  diff      dotfiles → HOME'
    ((${#filter[@]})) && title+="  [${filter[*]}]"
    header "$title"

    local row total=0 changed=0 missing=0 failed=0 only_home=0 only_repo=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        sync_row_selected "${filter[@]}" || continue
        ((total+=1))
        local hp rp out diff_rc
        hp="$(path_live_for "$S_MODE" "$S_SRC")"
        rp="$(path_repo_for "$S_MODE" "$S_SRC")"
        sync_classify "$hp" "$rp"
        case "$SYNC_CLASS" in
            MISSING) log_state MISSING "$S_NAME — немає ні в HOME, ні в dotfiles"; ((missing+=1)); continue ;;
            TARGET_ONLY) log_state DEL "$S_NAME — є в dotfiles, немає в HOME"; ((only_repo+=1)); continue ;;
            SOURCE_ONLY) log_state NEW "$S_NAME — є в HOME, немає в dotfiles"; ((only_home+=1)); continue ;;
            UNSAFE) log error "$S_NAME — небезпечний шлях"; ((failed+=1)); continue ;;
            SAME) continue ;;
            CHANGED) ((changed+=1)); log_state CHANGED "$S_NAME — є відмінності між HOME і dotfiles" ;;
            ERROR) log error "$S_NAME — помилка порівняння"; ((failed+=1)); continue ;;
        esac
        sync_report_nested_missing "$hp" "$rp" "$S_NAME" only_home only_repo
        local color_opt=--color=never
        _ui_tty 1 && color_opt=--color=always
        diff_rc=0
        if command -v git >/dev/null 2>&1; then
            out="$(git --no-pager diff --no-index "$color_opt" -- "$rp" "$hp" 2>&1)" || diff_rc=$?
        elif diff --color=always /dev/null /dev/null >/dev/null 2>&1; then
            out="$(diff "$color_opt" -ruN -- "$rp" "$hp" 2>&1)" || diff_rc=$?
        else
            out="$(diff -ruN -- "$rp" "$hp" 2>&1)" || diff_rc=$?
        fi
        if (( diff_rc > 1 )); then
            log error "diff: $S_NAME"
            ((failed+=1)); continue
        fi
        header "Diff: $S_NAME (dotfiles → HOME)"
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out"
        else
            log warn "$S_NAME — метадані різні, вміст однаковий"
        fi
    done
    printf '\n'
    log info "Diff: змінених $changed, тільки в HOME $only_home, тільки в dotfiles $only_repo, відсутніх $missing, помилок $failed (з $total записів)"
    ((failed == 0)) || return 2
    return 0
}

# Спільна перевірка фільтрів. На відміну від diff, невідомий фільтр — помилка.
sync_validate_filter() {
    local f row matched
    for f in "$@"; do
        matched=false
        for row in "${SRC_ROWS[@]}"; do
            sources_parse "$row"
            if [[ "$f" == "$S_NAME" || "$f" == "$S_SRC" || "$f" == "$S_REPO_REL" ]]; then
                matched=true
                break
            fi
        done
        if [[ "$matched" != true ]]; then
            log error "Немає шляху в реєстрі: $f"
            return 2
        fi
    done
}

sync_row_selected() {
    local f
    (($# == 0)) && return 0
    for f in "$@"; do
        [[ "$f" == "$S_NAME" || "$f" == "$S_SRC" || "$f" == "$S_REPO_REL" ]] && return 0
    done
    return 1
}

# verify: лише читання. Розбіжності — нормальний результат (код 0),
# помилки порівняння або невідомі фільтри — код 2.
sync_verify() {
    local -a filters=("$@")
    sources_load || return 2
    sync_validate_filter "${filters[@]}" || return 2
    header '✓  verify    HOME ↔ dotfiles (без змін)'
    local row home repo total=0 equal=0 changed=0 missing=0 failed=0 only_home=0 only_repo=0
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        sync_row_selected "${filters[@]}" || continue
        ((total+=1))
        home="$(path_live_for "$S_MODE" "$S_SRC")"
        repo="$(path_repo_for "$S_MODE" "$S_SRC")"
        sync_classify "$home" "$repo"
        case "$SYNC_CLASS" in
            MISSING) log_state MISSING "$S_NAME — немає ні в HOME, ні в dotfiles"; ((missing+=1)) ;;
            TARGET_ONLY) log_state DEL "$S_NAME — є в dotfiles, немає в HOME"; ((only_repo+=1)) ;;
            SOURCE_ONLY) log_state NEW "$S_NAME — є в HOME, немає в dotfiles"; ((only_home+=1)) ;;
            UNSAFE) log error "$S_NAME — небезпечний шлях"; ((failed+=1)) ;;
            SAME) log_state OK "$S_NAME"; ((equal+=1)) ;;
            CHANGED)
                log_state CHANGED "$S_NAME — є відмінності між HOME і dotfiles"
                ((changed+=1))
                sync_report_nested_missing "$home" "$repo" "$S_NAME" only_home only_repo ;;
            ERROR) log error "$S_NAME — помилка порівняння"; ((failed+=1)) ;;
        esac
    done
    printf '\n'
    log info "Verify: записів $total, однакових $equal, змінених $changed, тільки в HOME $only_home, тільки в dotfiles $only_repo, відсутніх $missing, помилок $failed"
    ((failed == 0)) || return 2
    return 0
}

# plan: без запису, перераховує заплановані операції з урахуванням sync-delete.
sync_plan() {
    local mode="${1:-}"; (($#)) && shift
    [[ "$mode" == backup || "$mode" == restore ]] || {
        log error 'Використання: dotfiles plan backup|restore [ШЛЯХ...]'
        return 2
    }
    local -a filters=("$@")
    sources_load || return 2
    sync_validate_filter "${filters[@]}" || return 2
    header "◇  plan $mode (лише читання)"
    local row src dst cmp_rc copied=0 updated=0 skipped=0 missing=0 failed=0 total=0
    local count_delete=0 extras
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        sync_row_selected "${filters[@]}" || continue
        ((total+=1))
        if [[ "$mode" == backup ]]; then
            src="$(path_live_for "$S_MODE" "$S_SRC")"
            dst="$(path_repo_for "$S_MODE" "$S_SRC")"
        else
            src="$(path_repo_for "$S_MODE" "$S_SRC")"
            dst="$(path_live_for "$S_MODE" "$S_SRC")"
        fi
        # Для plan класифікація залежить від напрямку backup/restore.
        # TARGET_ONLY також означає відсутність джерела.
        if [[ "${SYNC_DELETE:-false}" == true && -e "$dst" ]]; then
            sync_classify "$src" "$dst" full
        else
            sync_classify "$src" "$dst" copy
        fi
        case "$SYNC_CLASS" in
            MISSING|TARGET_ONLY)
                log warn "[MISSING] $S_NAME — немає джерела $src"
                ((missing+=1)); continue ;;
            UNSAFE|ERROR)
                log error "[ERROR] $S_NAME — небезпечний шлях або помилка порівняння"
                ((failed+=1)); continue ;;
            SOURCE_ONLY) cmp_rc=1 ;;
            SAME) cmp_rc=0 ;;
            CHANGED) cmp_rc=1 ;;
        esac
        # Навіть якщо цілі поки немає, перевіряємо безпеку майбутнього шляху.
        if ! path_ok_abs "$dst" || ! path_ok_source "$src"; then
            log error "[ERROR] $S_NAME — небезпечний шлях"
            ((failed+=1)); continue
        fi
        case "$cmp_rc" in
            0)
                if [[ -d "$src" && -d "$dst" && "${SYNC_DELETE:-false}" != true ]]; then
                    extras="$(fs_extras "$src" "$dst")"
                    if [[ -n "$extras" ]]; then
                        log_state KEEP_EXTRA "$S_NAME — зайві файли залишаться у призначенні"
                        ((skipped+=1))
                        continue
                    fi
                fi
                log_state SKIP "$S_NAME — без змін"
                ((skipped+=1)) ;;
            1)
                if [[ -e "$dst" ]]; then
                    if [[ -d "$src" && ! -d "$dst" ]] || [[ -f "$src" && ! -f "$dst" ]]; then
                        log error "[ERROR] $S_NAME — конфлікт типів"
                        ((failed+=1)); continue
                    fi
                    log_state UPDATE "$S_NAME — $src → $dst"
                    ((updated+=1))
                    if [[ "${SYNC_DELETE:-false}" == true ]]; then
                        extras="$(fs_extras "$src" "$dst")"
                        if [[ -n "$extras" ]]; then
                            log warn '  [DELETE] зайві файли в призначенні:'
                            printf '%s\n' "$extras"
                            ((count_delete+=1))
                        fi
                    fi
                else
                    log_state COPY "$S_NAME — $src → $dst"
                    ((copied+=1))
                fi ;;
            *) log error "[ERROR] $S_NAME — порівняння"; ((failed+=1)) ;;
        esac
    done
    printf '\n'
    log info "Plan: усього $total, створити $copied, оновити $updated, без змін $skipped, відсутніх $missing, помилок $failed"
    if (( count_delete )); then
        log warn "Sync-delete: $count_delete призначень містять зайві файли — перед реальною операцією зроби backup"
    fi
    (( failed == 0 ))
}
