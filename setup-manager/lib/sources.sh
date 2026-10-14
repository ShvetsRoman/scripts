#!/usr/bin/env bash
# Реєстр джерел. Формат: name | mode | src | dst | group.

sources_file() { printf '%s/config/sources.conf' "$ROOT_DIR"; }

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Єдина схема валідації для runtime, add і doctor.
sources_validate_fields() {
    [[ "$S_NAME" =~ ^[a-zA-Z0-9._-]+$ && "$S_NAME" != . && "$S_NAME" != .. ]] || {
        log error "Некоректне ім'я: $S_NAME"; return 2;
    }
    [[ "$S_MODE" == home || "$S_MODE" == abs || "$S_MODE" == system ]] || {
        log error "Некоректний режим: $S_MODE"; return 2;
    }
    [[ "$S_GROUP" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        log error "Некоректна група: $S_GROUP"; return 2;
    }
    path_ok_rel "$S_DST" && [[ "$S_DST" != */ ]] || {
        log error "Некоректне dst: $S_DST"; return 2;
    }
    if [[ "$S_MODE" == home ]]; then
        path_ok_rel "$S_SRC" && [[ "$S_SRC" != */ ]] || {
            log error "Некоректне src: $S_SRC"; return 2;
        }
    else
        path_syntax_abs "$S_SRC" && [[ "$S_SRC" != / ]] || {
            log error "Некоректне src: $S_SRC"; return 2;
        }
    fi
}

sources_overlap() {
    local old="$1" new="$2"
    [[ "$old" == "$new" || "$old" == "$new/"* || "$new" == "$old/"* ]]
}

sources_load() {
    SRC_ROWS=()
    local file line row prev
    local -A names=()
    file="$(sources_file)"
    [[ -f "$file" && ! -L "$file" ]] && path_ok_abs "$file" || {
        log error "Немає безпечного sources.conf: $file"; return 2;
    }
    local lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((lineno+=1))
        line="${line%%#*}"
        line="$(_trim "$line")"
        [[ -z "$line" ]] && continue
        [[ "${line//[^|]/}" == '||||' ]] || {
            log error "sources.conf:$lineno: очікується 5 полів"; return 2;
        }
        sources_parse "$line"
        sources_validate_fields || { log error "sources.conf:$lineno"; return 2; }
        [[ -z "${names[$S_NAME]:-}" ]] || {
            log error "sources.conf:$lineno: повторне ім'я $S_NAME"; return 2;
        }
        for prev in "${SRC_ROWS[@]}"; do
            local prev_dst
            IFS='|' read -r _ _ _ prev_dst _ <<< "$prev"
            prev_dst="$(_trim "$prev_dst")"
            if sources_overlap "$prev_dst" "$S_DST"; then
                log error "sources.conf:$lineno: шляхи призначення перетинаються: $prev_dst / $S_DST"
                return 2
            fi
        done
        names["$S_NAME"]=1
        SRC_ROWS+=("$line")
    done < "$file"
    return 0
}

sources_validate() {
    sources_load || return 2
    log ok "sources.conf: ${#SRC_ROWS[@]} записів, помилок немає"
}

# sources_parse — 5 полів: name | mode | src | dst | group.
# _normalize_dst — прибрати провідний '/' і подвійні '//' з dst.
_normalize_dst() {
    local d="$1"
    d="${d#/}"           # прибрати провідний /
    d="${d//\/\//\/}"   # замінити // на /
    while [[ "$d" == *"//"* ]]; do
        d="${d//\/\//\/}"
    done
    printf '%s' "$d"
}

sources_parse() {
    local row="$1"
    IFS='|' read -r S_NAME S_MODE S_SRC S_DST S_GROUP <<< "$row"
    S_NAME="$(_trim "$S_NAME")"
    S_MODE="$(_trim "$S_MODE")"
    S_SRC="$(_trim "$S_SRC")"
    S_DST="$(_trim "$S_DST")"
    S_GROUP="$(_trim "$S_GROUP")"
    S_GROUP="${S_GROUP:-dotfiles}"
}

# sources_abs — абсолютний шлях src для mode.
sources_abs() {
    local mode="$1" src="$2"
    if [[ "$mode" == home ]]; then
        printf '%s/%s' "$HOME" "$src"
    else
        printf '%s' "$src"
    fi
}

# sources_find — знайти рядок за іменем. Заповнює S_* у поточному shell.
sources_find() {
    local name="$1"
    sources_load || return 2
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        if [[ "$S_NAME" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}

# sources_add — name mode src dst [group]
sources_add() {
    local name mode src dst group row
    if (($# == 3)); then
        # Зворотна сумісність зі старою довідкою: MODE SRC DST.
        mode="$1"; src="$2"; dst="$3"; name="$(basename -- "${dst%/}")"; group=dotfiles
    elif (($# >= 4 && $# <= 5)); then
        name="$1"; mode="$2"; src="$3"; dst="$4"; group="${5:-dotfiles}"
    else
        log error 'sources add [NAME] MODE SRC DST [GROUP]'; return 2
    fi
    S_NAME="$name"; S_MODE="$mode"; S_SRC="$src"; S_DST="$dst"; S_GROUP="$group"
    sources_validate_fields || return 2
    if [[ "$mode" != home ]]; then
        path_ok_abs "$src" || { log error "Небезпечне джерело: $src"; return 2; }
    fi
    sources_load || return 2
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        if [[ "$S_NAME" == "$name" ]] || sources_overlap "$S_DST" "$dst"; then
            log error "Зайнято name або перетин dst: $name / $dst"; return 1
        fi
    done
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] sources add: $name → $src ($dst)"; return 0
    fi
    path_ok_abs "$(sources_file)" || { log error 'Небезпечний sources.conf'; return 2; }
    printf '%s | %s | %s | %s | %s\n' "$name" "$mode" "$src" "$dst" "$group" >> "$(sources_file)" || return 2
    log ok "Додано: $name → $mode $src ($dst)"
}

# sources_remove — за іменем.
sources_remove() {
    local name="${1:-}" file tmp removed=0 row
    [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || { log error 'Некоректне name'; return 2; }
    sources_load || return 2
    file="$(sources_file)"
    [[ -f "$file" ]] || { log warn 'Реєстр порожній'; return 0; }
    local exists=false
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        [[ "$S_NAME" == "$name" ]] && exists=true
    done
    if [[ "$exists" == false ]]; then log warn "Не знайдено: $name"; return 0; fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] sources remove: $name"; return 0
    fi
    path_ok_abs "$file" || { log error 'Небезпечний sources.conf'; return 2; }
    tmp="$(mktemp "${file}.tmp.XXXXXXXX")" || return 2
    while IFS= read -r row || [[ -n "$row" ]]; do
        local stripped="${row%%#*}"
        if [[ -n "$(_trim "$stripped")" ]]; then
            sources_parse "$row"
            if [[ "$S_NAME" == "$name" ]]; then
                removed=1; continue
            fi
        fi
        printf '%s\n' "$row" >> "$tmp" || { rm -f -- "$tmp"; return 2; }
    done < "$file"
    chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 2; }
    mv -- "$tmp" "$file" || { rm -f -- "$tmp"; return 2; }
    (( removed )) && log ok "Видалено: $name" || log warn "Не знайдено: $name"
    return 0
}

sources_list() {
    sources_load || return 2
    ((${#SRC_ROWS[@]})) || { log info 'Джерел немає.'; return 0; }
    printf '%-20s %-5s %-42s %-42s %s\n' NAME MODE SRC DST GROUP
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        printf '%-20s %-5s %-42s %-42s %s\n' "$S_NAME" "$S_MODE" "$S_SRC" "$S_DST" "$S_GROUP"
    done
}

sources_doctor() {
    sources_load || return 2
    ((${#SRC_ROWS[@]})) || { log info 'Реєстр порожній.'; return 0; }
    local ok=0 bad=0 miss=0
    printf '%-20s %-5s %-42s %-7s %-42s %-7s\n' NAME MODE ABS-SRC EXISTS DST REPO
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        local abs src_ok='no' dst_ok='no'
        abs="$(sources_abs "$S_MODE" "$S_SRC")"
        [[ -e "$abs" || -L "$abs" ]] && src_ok='yes'
        [[ -e "$ROOT_DIR/dotfiles/$S_DST" || -L "$ROOT_DIR/dotfiles/$S_DST" ]] && dst_ok='yes'
        printf '%-20s %-5s %-42s %-7s %-42s %-7s\n' "$S_NAME" "$S_MODE" "$abs" "$src_ok" "$S_DST" "$dst_ok"
        if [[ "$src_ok" == no && "$dst_ok" == no ]]; then
            ((miss+=1))
        elif [[ "$src_ok" == no || "$dst_ok" == no ]]; then
            ((bad+=1))
        else
            ((ok+=1))
        fi
    done
    printf '\nРазом: %d OK, %d частково, %d відсутні\n' "$ok" "$bad" "$miss"
}
