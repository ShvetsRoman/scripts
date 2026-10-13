#!/usr/bin/env bash
# Реєстр джерел. Формат: name | mode | src | dst | group.

sources_file() { printf '%s/config/sources.conf' "$ROOT_DIR"; }

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

sources_load() {
    SRC_ROWS=()
    local file; file="$(sources_file)"
    [[ -f "$file" ]] || return 0
    local line
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(_trim "$line")"
        [[ -z "$line" ]] && continue
        SRC_ROWS+=("$line")
    done < "$file"
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
    S_DST="$(_normalize_dst "$S_DST")"
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
    sources_load
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
    local name="$1" mode="$2" src="$3" dst="$4" group="${5:-dotfiles}"
    [[ -n "$name" ]] || { log error 'name порожній'; return 2; }
    [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || { log error "name: $name"; return 2; }
    [[ "$mode" == home || "$mode" == abs ]] || { log error 'mode: home|abs'; return 2; }
    dst="$(_normalize_dst "$dst")"
    path_ok_rel "$dst" || { log error "dst має бути відносним: $dst"; return 2; }
    if [[ "$mode" == abs ]]; then
        path_ok_abs "$src" || { log error "src: $src"; return 2; }
    else
        path_ok_rel "$src" || { log error "src: $src"; return 2; }
    fi

    sources_load
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        [[ "$S_NAME" == "$name" ]] && { log error "name зайнято: $name"; return 1; }
    done

    printf '%s | %s | %s | %s | %s\n' "$name" "$mode" "$src" "$dst" "$group" >> "$(sources_file)"
    log ok "Додано: $name → $mode $src ($dst)"
}

# sources_remove — за іменем.
sources_remove() {
    local name="$1"
    [[ -n "$name" ]] || { log error 'name порожній'; return 2; }
    local file; file="$(sources_file)"
    [[ -f "$file" ]] || { log warn 'Реєстр порожній'; return 0; }
    local tmp; tmp="$(mktemp)"
    local removed=0 row
    while IFS= read -r row; do
        local stripped="${row%%#*}"
        if [[ -n "${stripped// /}" ]]; then
            sources_parse "$row"
            if [[ "$S_NAME" == "$name" ]]; then
                removed=1; continue
            fi
        fi
        printf '%s\n' "$row" >> "$tmp"
    done < "$file"
    mv -- "$tmp" "$file"
    (( removed )) && log ok "Видалено: $name" || log warn "Не знайдено: $name"
}

sources_list() {
    sources_load
    ((${#SRC_ROWS[@]})) || { log info 'Джерел немає.'; return 0; }
    printf '%-20s %-5s %-42s %-42s %s\n' NAME MODE SRC DST GROUP
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        printf '%-20s %-5s %-42s %-42s %s\n' "$S_NAME" "$S_MODE" "$S_SRC" "$S_DST" "$S_GROUP"
    done
}

sources_doctor() {
    sources_load
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
