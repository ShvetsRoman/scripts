# ============================================================
# FZF CONFIGURATION
# ============================================================
# Ctrl+T - Пошук файлів
# Alt+C - Пошук директорій
# fcd — перейти в каталог
# fvim — знайти та відкрити файл у Neovim
# frg текст — знайти текст у файлах та відкрити точний рядок
# fkill — вибрати процес
# fgit — перегляд commit'ів
# fgbranch — переключення гілки
# fgfile — Git-файли зі змінами
# fpacman — інформація про встановлений пакет
# fparu — пошук пакетів
# fremove — інтерактивне видалення пакетів
# ============================================================

# ------------------------------------------------------------
# Базові команди пошуку
# ------------------------------------------------------------

if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# ------------------------------------------------------------
# Загальні параметри fzf
# ------------------------------------------------------------

export FZF_DEFAULT_OPTS='
    --height=70%
    --layout=reverse
    --border=rounded
    --info=inline
    --prompt="❯ "
    --pointer="▶"
    --marker="✓"
    --cycle
'

# ------------------------------------------------------------
# Ctrl+T - Пошук файлів
# ------------------------------------------------------------

if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS='
        --preview "bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null"
        --preview-window=right:60%
    '
fi

# ------------------------------------------------------------
# Alt+C - Пошук директорій
# ------------------------------------------------------------

if command -v eza >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS='
        --preview "eza --tree --level=2 --icons --color=always {} 2>/dev/null"
        --preview-window=right:60%
    '
fi

# ============================================================
# FCD - Інтерактивний перехід у директорію
# ============================================================

fcd() {
    local dir

    if ! command -v fd >/dev/null 2>&1; then
        echo "Помилка: команда fd не знайдена."
        return 1
    fi

    if command -v eza >/dev/null 2>&1; then
        dir="$(
            fd --type d --hidden --follow --exclude .git . "${1:-.}" |
                fzf \
                    --prompt='Directory ❯ ' \
                    --preview='eza --tree --level=2 --icons --color=always {} 2>/dev/null'
        )"

        if [[ $? -ne 0 ]]; then
            return 0
        fi
    else
        dir="$(
            fd --type d --hidden --follow --exclude .git . "${1:-.}" |
                fzf --prompt='Directory ❯ '
        )"

        if [[ $? -ne 0 ]]; then
            return 0
        fi
    fi

    if [[ -n "$dir" ]]; then
        cd -- "$dir"
    fi
}

# ============================================================
# FFILE - Інтерактивний вибір файлу
# ============================================================

ffile() {
    local file

    if ! command -v fd >/dev/null 2>&1; then
        echo "Помилка: команда fd не знайдена."
        return 1
    fi

    if command -v bat >/dev/null 2>&1; then
        file="$(
            fd --type f --hidden --follow --exclude .git . "${1:-.}" |
                fzf \
                    --prompt='File ❯ ' \
                    --preview='bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null'
        )"
    else
        file="$(
            fd --type f --hidden --follow --exclude .git . "${1:-.}" |
                fzf --prompt='File ❯ '
        )"
    fi

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -n "$file" ]]; then
        print -r -- "$file"
    fi
}

# ============================================================
# FVIM - Пошук файлу та відкриття у Neovim
# ============================================================

fvim() {
    local file

    if ! command -v fd >/dev/null 2>&1; then
        echo "Помилка: команда fd не знайдена."
        return 1
    fi

    if ! command -v nvim >/dev/null 2>&1; then
        echo "Помилка: команда nvim не знайдена."
        return 1
    fi

    if command -v bat >/dev/null 2>&1; then
        file="$(
            fd --type f --hidden --follow --exclude .git |
                fzf \
                    --prompt='Neovim ❯ ' \
                    --preview='bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null'
        )"
    else
        file="$(
            fd --type f --hidden --follow --exclude .git |
                fzf --prompt='Neovim ❯ '
        )"
    fi

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -n "$file" ]]; then
        nvim -- "$file"
    fi
}

ff() { fvim "$@"; }

# ============================================================
# FRG - Пошук тексту через ripgrep
# ============================================================

frg() {
    local result
    local file
    local line
    local query="${1:-}"

    if ! command -v rg >/dev/null 2>&1; then
        echo "Помилка: команда rg не знайдена."
        return 1
    fi

    if ! command -v nvim >/dev/null 2>&1; then
        echo "Помилка: команда nvim не знайдена."
        return 1
    fi

    if command -v bat >/dev/null 2>&1; then
        result="$(
            rg \
                --line-number \
                --no-heading \
                --color=always \
                --smart-case \
                "$query" |
                fzf \
                    --ansi \
                    --delimiter=: \
                    --prompt='Ripgrep ❯ ' \
                    --preview='bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null' \
                    --preview-window='right:60%:+{2}'
        )"
    else
        result="$(
            rg \
                --line-number \
                --no-heading \
                --color=always \
                --smart-case \
                "$query" |
                fzf \
                    --ansi \
                    --delimiter=: \
                    --prompt='Ripgrep ❯ '
        )"
    fi

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -z "$result" ]]; then
        return 0
    fi

    file="${result%%:*}"
    line="${result#*:}"
    line="${line%%:*}"

    nvim +"$line" -- "$file"
}

# ============================================================
# FKILL - Інтерактивне завершення процесів
# ============================================================

fkill() {
    local selected
    local signal="${1:-15}"

    selected="$(
        ps -ef |
            sed 1d |
            fzf \
                --multi \
                --prompt='Kill ❯ ' \
                --header='TAB: вибрати кілька процесів'
    )"

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -z "$selected" ]]; then
        return 0
    fi

    print -r -- "$selected" |
        awk '{print $2}' |
        xargs -r kill "-$signal"
}

# ============================================================
# FGIT - Перегляд Git commit
# ============================================================

fgit() {
    local commit
    local hash

    if ! command -v git >/dev/null 2>&1; then
        echo "Помилка: команда git не знайдена."
        return 1
    fi

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Поточна директорія не є Git-репозиторієм."
        return 1
    fi

    commit="$(
        git log \
            --graph \
            --color=always \
            --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \
            --all |
            fzf \
                --ansi \
                --no-sort \
                --prompt='Git commit ❯ ' \
                --preview='
                hash=$(echo {} | grep -o "[a-f0-9]\{7,\}" | head -1)
                if [[ -n "$hash" ]]; then
                    git show --color=always "$hash"
                fi
            ' \
                --preview-window=right:60%
    )"

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -z "$commit" ]]; then
        return 0
    fi

    hash="$(
        grep -o '[a-f0-9]\{7,\}' <<<"$commit" |
            head -1
    )"

    if [[ -n "$hash" ]]; then
        git show "$hash"
    fi
}

# ============================================================
# FGBRANCH - Інтерактивне переключення Git branch
# ============================================================

fgbranch() {
    (($+commands[git] && $+commands[fzf])) || return 127
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    local branch code
    branch=$(git branch --all --format='%(refname:short)' | grep -v 'HEAD$' | fzf --prompt='Git branch ❯ ')
    code=$?
    ((code == 1 || code == 130)) && return 0
    ((code != 0)) && return "$code"
    [[ -n "$branch" ]] || return 0
    if [[ "$branch" == */* ]] && ! git show-ref --verify --quiet "refs/heads/$branch"; then
        # Git сам визначає tracking branch лише за однозначного відповідника.
        git switch --track "$branch"
    else
        git switch -- "$branch"
    fi
}

# ============================================================
# FGFILE - Git-файли зі змінами
# ============================================================

fgfile() {
    (($+commands[git] && $+commands[fzf] && $+commands[nvim])) || return 127
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    local file code
    # NUL-розділювач зберігає пробіли, переноси та спецсимволи у шляхах.
    file=$(git -c core.quotepath=false status --porcelain=v1 -z | python3 -c '
import sys
raw=sys.stdin.buffer.read().split(b"\0")
names=[]
i=0
while i < len(raw):
    entry=raw[i]
    if not entry: break
    status=entry[:2]
    name=entry[3:]
    if status[:1] in (b"R", b"C") or status[1:] in (b"R", b"C"):
        i+=1
        # Для перейменування перше ім’я — актуальний шлях, друге — старий.
        # Пропускаємо старе ім’я, але зберігаємо актуальний шлях.
    names.append(name)
    i+=1
sys.stdout.buffer.write(b"\0".join(names)+b"\0" if names else b"")
' | fzf --read0 --print0 --prompt='Git file ❯ ' | tr -d '\0')
    code=$?
    ((code == 1 || code == 130)) && return 0
    ((code != 0)) && return "$code"
    [[ -n "$file" ]] && nvim -- "$file"
}

# ============================================================
# FPACMAN - Пошук встановлених пакетів
# ============================================================

fpacman() {
    local selected
    local package

    if ! command -v pacman >/dev/null 2>&1; then
        echo "Помилка: команда pacman не знайдена."
        return 1
    fi

    selected="$(
        pacman -Q |
            fzf \
                --prompt='Pacman ❯ ' \
                --preview='
                pkg=$(echo {} | awk "{print \$1}")
                pacman -Qi "$pkg"
            ' \
                --preview-window=right:60%
    )"

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -z "$selected" ]]; then
        return 0
    fi

    package="${selected%% *}"

    pacman -Qi "$package"
}

# ============================================================
# FPARU - Пошук пакетів через paru
# ============================================================

fparu() {
    local package

    if ! command -v paru >/dev/null 2>&1; then
        echo "Помилка: команда paru не знайдена."
        return 1
    fi

    package="$(
        paru -Slq |
            sort -u |
            fzf \
                --prompt='Paru ❯ ' \
                --preview='
                paru -Si {} 2>/dev/null
                if [[ $? -ne 0 ]]; then
                    paru -Qi {} 2>/dev/null
                fi
            ' \
                --preview-window=right:60%
    )"

    local fzf_result=$?
    if ((fzf_result == 1 || fzf_result == 130)); then
        return 0
    elif ((fzf_result != 0)); then
        return "$fzf_result"
    fi

    if [[ -n "$package" ]]; then
        paru -Si "$package"
    fi
}

# ============================================================
# FREMOVE - Інтерактивне видалення пакетів
# ============================================================

fremove() {
    (($+commands[pacman] && $+commands[fzf])) || return 127
    local selected code
    local -a packages
    selected=$(pacman -Qq | fzf --multi --prompt='Remove package ❯ ' --header='Tab: вибір пакетів' --preview='pacman -Qi {}')
    code=$?
    ((code == 1 || code == 130)) && return 0
    ((code != 0)) && return "$code"
    [[ -n "$selected" ]] || return 0
    packages=("${(@f)selected}")
    print -r -- 'Обрано для видалення:'
    printf '  %s\n' "${packages[@]}"
    read -r '?Підтвердити видалення? [y/N] ' answer
    [[ "$answer" == [yY] || "$answer" == yes ]] || return 0
    sudo pacman -Rns -- "${packages[@]}"
}

# Ініціалізація офіційних Ctrl+R, Ctrl+T, Alt+C.
eval "$(fzf --zsh)"
