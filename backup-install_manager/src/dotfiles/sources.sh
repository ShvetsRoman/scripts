#!/usr/bin/env bash
# Єдиний формат реєстру: ID | TYPE | PATH. Групи — [section].

sources_file() { path_config dotfiles.conf; }
_trim_r() {
    REPLY="${1#"${1%%[![:space:]]*}"}"
    REPLY="${REPLY%"${REPLY##*[![:space:]]}"}"
}
sources_parse() {
    local row="$1"
    IFS='|' read -r S_NAME S_MODE S_SRC <<< "$row"
    _trim_r "$S_NAME"; S_NAME="$REPLY"
    _trim_r "$S_MODE"; S_MODE="$REPLY"
    _trim_r "$S_SRC"; S_SRC="$REPLY"
    # Єдине місце розгортання HOME та формування репозиторного шляху.
    path_resolve "$S_MODE" "$S_SRC"
    # Використовується sync.sh, меню та одноразовою міграцією.
    # shellcheck disable=SC2034
    S_REPO_REL="$PATH_REL"
}
sources_validate_fields() {
    [[ "$S_NAME" =~ ^[a-zA-Z0-9._-]+$ && "$S_NAME" != . && "$S_NAME" != .. ]] || {
        log error "Некоректний ID: $S_NAME"; return 2;
    }
    path_resolve "$S_MODE" "$S_SRC" || {
        log error "Некоректний TYPE/PATH: $S_MODE | $S_SRC"; return 2;
    }
    path_ok_abs "$PATH_REPO" || {
        log error "Небезпечний шлях у сховищі: $PATH_REPO"; return 2;
    }
}
sources_overlap() {
    local old="$1" new="$2"
    [[ "$old" == "$new" || "$old" == "$new/"* || "$new" == "$old/"* ]]
}
sources_load() {
    SRC_ROWS=()
    DOTFILES_GROUPS=()
    declare -gA DOTFILES_ITEM_GROUP=()
    local file line group_name section="" lineno=0 prev
    local -A seen_group=() seen_id=() seen_live=() seen_repo=()
    file="$(sources_file)"
    [[ -f "$file" && ! -L "$file" ]] && path_ok_abs "$file" || {
        log error "Немає безпечного dotfiles.conf: $file"; return 2;
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((lineno+=1))
        line="${line%%#*}"
        _trim_r "$line"; line="$REPLY"
        [[ -z "$line" ]] && continue
        if [[ "$line" == \[*\] ]]; then
            group_name="${line:1:${#line}-2}"
            [[ "$group_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ && ! -v seen_group["$group_name"] ]] || {
                log error "dotfiles.conf:$lineno: дубль або некоректна група: $group_name"; return 2;
            }
            seen_group["$group_name"]=1
            DOTFILES_GROUPS+=("$group_name")
            section="$group_name"
            continue
        fi
        [[ -n "$section" && "${line//[^|]/}" == '||' ]] || {
            log error "dotfiles.conf:$lineno: очікується [group] і рівно 3 поля"; return 2;
        }
        sources_parse "$line" || { log error "dotfiles.conf:$lineno: некоректний шлях"; return 2; }
        sources_validate_fields || { log error "dotfiles.conf:$lineno"; return 2; }
        [[ ! -v seen_id["$S_NAME"] ]] || { log error "Повторний ID $S_NAME"; return 2; }
        for prev in "${!seen_live[@]}"; do
            sources_overlap "$prev" "$PATH_LIVE" && { log error "Перетин шляхів: $prev / $PATH_LIVE"; return 2; }
        done
        for prev in "${!seen_repo[@]}"; do
            sources_overlap "$prev" "$PATH_REPO" && { log error "Перетин сховища: $prev / $PATH_REPO"; return 2; }
        done
        seen_id["$S_NAME"]=1
        seen_live["$PATH_LIVE"]=1
        seen_repo["$PATH_REPO"]=1
        DOTFILES_ITEM_GROUP["$S_NAME"]="$section"
        SRC_ROWS+=("$line")
    done < "$file"
    return 0
}
sources_validate() {
    sources_load || return 2
    log ok "dotfiles.conf: ${#SRC_ROWS[@]} записів, помилок немає"
}
sources_find() {
    local name="$1" row
    [[ "${SRC_ROWS+x}" == x ]] || sources_load || return 2
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row" || return 2
        [[ "$S_NAME" == "$name" ]] && return 0
    done
    return 1
}
# Додавання тільки у вказану групу, яка має бути останньою в реєстрі.
sources_add() {
    local name="${1:-}" mode="${2:-}" src="${3:-}" group="${4:-}" row
    local live repo file last_byte
    (($# == 4)) || { log error 'sources add NAME TYPE PATH GROUP'; return 2; }
    S_NAME="$name"; S_MODE="$mode"; S_SRC="$src"
    sources_validate_fields || return 2
    live="$PATH_LIVE"; repo="$PATH_REPO"
    sources_load || return 2
    [[ "${DOTFILES_GROUPS[-1]:-}" == "$group" ]] || {
        log error "Для додавання група $group має бути останньою у dotfiles.conf"; return 2;
    }
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row" || return 2
        if [[ "$S_NAME" == "$name" ]] || sources_overlap "$PATH_LIVE" "$live" || sources_overlap "$PATH_REPO" "$repo"; then
            log error "Дубль ID або перетин шляхів для $name"
            return 2
        fi
    done
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] sources add: $name"; return 0
    fi
    file="$(sources_file)"
    path_ok_abs "$file" || return 2
    # Не зливаємо два записи, якщо файл закінчується без newline.
    last_byte="$(tail -c 1 -- "$file" | od -An -tu1 | tr -d '[:space:]')"
    if [[ -n "$last_byte" && "$last_byte" != 10 ]]; then
        printf '\n' >> "$file" || return 2
    fi
    printf '%s | %s | %s\n' "$name" "$mode" "$src" >> "$file" || return 2
    log ok "Додано: $name"
}

sources_remove() {
    local name="${1:-}" line tmp file
    [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || return 2
    sources_load || return 2
    file="$(sources_file)"
    if [[ "${DRY_RUN:-false}" == true ]]; then log info "[DRY-RUN] sources remove: $name"; return 0; fi
    tmp="$(mktemp "${file}.tmp.XXXXXXXX")" || return 2
    while IFS= read -r line || [[ -n "$line" ]]; do
        local plain="${line%%#*}"
        _trim_r "$plain"; plain="$REPLY"
        if [[ "$plain" == *'|'* ]]; then
            sources_parse "$plain" || { rm -f -- "$tmp"; return 2; }
            [[ "$S_NAME" == "$name" ]] && continue
        fi
        printf '%s\n' "$line" >> "$tmp" || { rm -f -- "$tmp"; return 2; }
    done < "$file"
    chmod --reference="$file" "$tmp" && mv -- "$tmp" "$file" || { rm -f -- "$tmp"; return 2; }
    log ok "Видалено: $name"
}
sources_list() {
    sources_load || return 2
    printf '%-20s %-8s %-48s %s\n' ID TYPE PATH GROUP
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row" || return 2
        printf '%-20s %-8s %-48s %s\n' "$S_NAME" "${S_MODE:--}" "$S_SRC" "${DOTFILES_ITEM_GROUP[$S_NAME]}"
    done
}
sources_doctor() {
    sources_load || return 2
    printf '%-20s %-46s %-7s %-46s %-7s\n' ID LIVE EXISTS REPO EXISTS
    local row src_ok repo_ok
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row" || return 2
        src_ok=no; repo_ok=no
        [[ -e "$PATH_LIVE" || -L "$PATH_LIVE" ]] && src_ok=yes
        [[ -e "$PATH_REPO" || -L "$PATH_REPO" ]] && repo_ok=yes
        printf '%-20s %-46s %-7s %-46s %-7s\n' "$S_NAME" "$PATH_LIVE" "$src_ok" "$PATH_REPO" "$repo_ok"
    done
}
sources_groups() {
    sources_load || return 2
    local group row count
    printf '%-22s %s\n' 'ГРУПА' 'КІЛЬКІСТЬ'
    for group in "${DOTFILES_GROUPS[@]}"; do
        count=0
        for row in "${SRC_ROWS[@]}"; do
            sources_parse "$row" || return 2
            [[ "${DOTFILES_ITEM_GROUP[$S_NAME]}" == "$group" ]] && ((count+=1))
        done
        printf '%-22s %d\n' "$group" "$count"
    done
}
