#!/usr/bin/env bash
# Реєстр джерел.

# sources_file — шлях до реєстру.
sources_file() { printf '%s/config/sources.conf' "$ROOT_DIR"; }

# _trim — видаляє всі пробіли/таби з обох кінців рядка.
_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# sources_load — читає реєстр у масив SRC_ROWS.
# Ігнорує порожні рядки та коментарі (#).
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

# sources_parse — розбирає рядок у змінні S_MODE, S_SRC, S_DST, S_GROUP.
# Обрізає пробіли навколо кожного поля (щоб `a | b | c` працювало).
sources_parse() {
    local row="$1"
    IFS='|' read -r S_MODE S_SRC S_DST S_GROUP <<< "$row"
    S_MODE="$(_trim "$S_MODE")"
    S_SRC="$(_trim "$S_SRC")"
    S_DST="$(_trim "$S_DST")"
    S_GROUP="$(_trim "$S_GROUP")"
    S_GROUP="${S_GROUP:-dotfiles}"
}

# sources_abs — перетворює mode+src у абсолютний шлях.
# home: $HOME/src; abs: src як є.
sources_abs() {
    local mode="$1" src="$2"
    if [[ "$mode" == home ]]; then
        printf '%s/%s' "$HOME" "$src"
    else
        printf '%s' "$src"
    fi
}

# sources_add — додає новий рядок у реєстр.
# Аргументи: mode (home|abs), src, dst, [group=dotfiles].
# Перевіряє безпечність шляхів і відсутність дубляка dst.
sources_add() {
    local mode="$1" src="$2" dst="$3" group="${4:-dotfiles}"
    [[ "$mode" == home || "$mode" == abs ]] || { log error 'mode: home|abs'; return 2; }
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
        [[ "$S_DST" == "$dst" ]] && { log error "dst зайнято: $dst"; return 1; }
    done

    printf '%s | %s | %s | %s\n' "$mode" "$src" "$dst" "$group" >> "$(sources_file)"
    log ok "Додано: $mode $src → dotfiles/$dst"
}

# sources_remove — видаляє рядок за dst.
# Переписує файл, зберігаючи коментарі та порожні рядки.
sources_remove() {
    local dst="$1"
    path_ok_rel "$dst" || { log error "dst: $dst"; return 2; }
    local file; file="$(sources_file)"
    [[ -f "$file" ]] || { log warn 'Реєстр порожній'; return 0; }
    local tmp; tmp="$(mktemp)"
    local removed=0 row
    while IFS= read -r row; do
        local stripped="${row%%#*}"
        if [[ -n "${stripped// /}" ]]; then
            sources_parse "$row"
            if [[ "$S_DST" == "$dst" ]]; then
                removed=1; continue
            fi
        fi
        printf '%s\n' "$row" >> "$tmp"
    done < "$file"
    mv -- "$tmp" "$file"
    (( removed )) && log ok "Видалено: $dst" || log warn "Не знайдено: $dst"
}

# sources_list — виводить таблицю реєстру.
sources_list() {
    sources_load
    ((${#SRC_ROWS[@]})) || { log info 'Джерел немає.'; return 0; }
    printf '%-5s %-45s %-40s %s\n' MODE SRC DST GROUP
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        printf '%-5s %-45s %-40s %s\n' "$S_MODE" "$S_SRC" "$S_DST" "$S_GROUP"
    done
}

# sources_doctor — діагностика реєстру.
# Для кожного рядка показує: абсолютний src, чи існує, dst, чи існує в репо.
# Наприкінці — підсумок: OK / частково / відсутні.
sources_doctor() {
    sources_load
    ((${#SRC_ROWS[@]})) || { log info 'Реєстр порожній.'; return 0; }

    local ok=0 bad=0 miss=0
    printf '%-5s %-45s %-7s %-35s %-7s\n' MODE ABS-SRC EXISTS DST REPO
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        local abs src_ok='no' dst_ok='no'
        abs="$(sources_abs "$S_MODE" "$S_SRC")"
        [[ -e "$abs" || -L "$abs" ]] && src_ok='yes'
        [[ -e "$ROOT_DIR/dotfiles/$S_DST" || -L "$ROOT_DIR/dotfiles/$S_DST" ]] && dst_ok='yes'
        printf '%-5s %-45s %-7s %-35s %-7s\n' "$S_MODE" "$abs" "$src_ok" "$S_DST" "$dst_ok"

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
