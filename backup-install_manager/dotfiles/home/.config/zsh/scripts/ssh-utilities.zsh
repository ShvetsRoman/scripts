# ============================================================
# SSH UTILITIES v1.0
# Набір команд для керування SSH у Zsh
# Arch Linux
# ============================================================

# ============================================================
# КОЛЬОРОВА ПАЛІТРА
# ============================================================

# Автоматично вимикаємо кольори, якщо:
# - вивід перенаправлений;
# - встановлена змінна NO_COLOR.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    SSH_COLOR_RESET=$'\033[0m'
    SSH_COLOR_RED=$'\033[31m'
    SSH_COLOR_GREEN=$'\033[32m'
    SSH_COLOR_YELLOW=$'\033[33m'
    SSH_COLOR_BLUE=$'\033[34m'
    SSH_COLOR_CYAN=$'\033[36m'
    SSH_COLOR_GRAY=$'\033[90m'
    SSH_COLOR_BOLD=$'\033[1m'
else
    SSH_COLOR_RESET=''
    SSH_COLOR_RED=''
    SSH_COLOR_GREEN=''
    SSH_COLOR_YELLOW=''
    SSH_COLOR_BLUE=''
    SSH_COLOR_CYAN=''
    SSH_COLOR_GRAY=''
    SSH_COLOR_BOLD=''
fi

# ============================================================
# ДОПОМІЖНІ ФУНКЦІЇ
# ============================================================

# Виведення повідомлення про успіх.
# Друк через print -r, а не print -P: кольори вже містять готові
# ANSI-послідовності, а print -P розгортав би prompt-escape (%d, %n
# тощо) у даних користувача, наприклад у шляхах до ключів.
_ssh_success() {
    print -r -- "${SSH_COLOR_GREEN}✔${SSH_COLOR_RESET} $*"
}

# Виведення попередження
_ssh_warning() {
    print -r -- "${SSH_COLOR_YELLOW}⚠${SSH_COLOR_RESET} $*"
}

# Виведення помилки
_ssh_error() {
    print -r -- "${SSH_COLOR_RED}✘${SSH_COLOR_RESET} $*" >&2
}

# Виведення інформації
_ssh_info() {
    print -r -- "${SSH_COLOR_CYAN}ℹ${SSH_COLOR_RESET} $*"
}

# Перевірка наявності SSH-клієнта
_ssh_require_client() {
    if ! command -v ssh >/dev/null 2>&1; then
        _ssh_error "SSH-клієнт не встановлений."
        return 1
    fi
}

# Перевірка наявності конфігурації
_ssh_require_config() {
    if [[ ! -f "$HOME/.ssh/config" ]]; then
        _ssh_error "Файл ~/.ssh/config не знайдений."
        return 1
    fi
}

# Витягує імена хостів із ~/.ssh/config.
# Спільна логіка для ssh-list та ssh-check: виключає коментарі,
# wildcard-шаблони (*, ?) та заперечення (!host).
_ssh_config_hosts() {
    awk '
        /^[[:space:]]*#/ { next }
        tolower($1) == "host" {
            for (i = 2; i <= NF; i++) {
                if ($i !~ /[*?!]/ && $i !~ /^!/) {
                    print $i
                }
            }
        }
    ' "$HOME/.ssh/config" | sort -u
}

# ============================================================
# 1. SSH-LIST
# Список налаштованих SSH-підключень
# ============================================================

ssh-list() {
    _ssh_require_client || return 1
    _ssh_require_config || return 1

    local host
    local details
    local hostname
    local username
    local port
    local count=0

    print
    print -r -- "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH CONNECTIONS${SSH_COLOR_RESET}"
    print -r -- "${SSH_COLOR_GRAY}Налаштовані SSH-підключення${SSH_COLOR_RESET}"
    print

    # Отримуємо назви Host з конфігурації.
    # Виключаємо шаблони та wildcard-записи.

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        # ssh -G повертає ефективну конфігурацію для хоста.
        # Він не перевіряє доступність (завжди завершується успішно
        # з дефолтними значеннями), тому аналізуємо лише результат.
        details="$(ssh -G "$host" 2>/dev/null)"
        [[ -n "$details" ]] || continue

        hostname="$(print -r -- "$details" |
            awk '$1 == "hostname" {print $2; exit}')"

        username="$(print -r -- "$details" |
            awk '$1 == "user" {print $2; exit}')"

        port="$(print -r -- "$details" |
            awk '$1 == "port" {print $2; exit}')"

        printf "  ${SSH_COLOR_GREEN}%-20s${SSH_COLOR_RESET} %s\n" \
            "$host" "$hostname"

        printf "  ${SSH_COLOR_GRAY}%-20s${SSH_COLOR_RESET} %s\n" \
            "User:" "$username"

        printf "  ${SSH_COLOR_GRAY}%-20s${SSH_COLOR_RESET} %s\n" \
            "Port:" "$port"

        print
        ((count++))

    done < <(_ssh_config_hosts)

    if ((count == 0)); then
        _ssh_warning "SSH-підключення не знайдені."
    else
        _ssh_success "Знайдено підключень: $count"
    fi

    return 0
}

# ============================================================
# 2. SSH-CHECK
# Перевірка доступності SSH-серверів
# ============================================================

ssh-check() {
    _ssh_require_client || return 1

    local host
    local exit_code
    local checked=0
    local failed=0

    if (($# > 0)); then
        # Кожен аргумент — окремий хост. Пробіли у destination
        # для ssh некоректні, тому відхиляємо їх одразу
        # з зрозумілим повідомленням замість загадкового FAIL.
        local host_arg
        for host_arg in "$@"; do
            if [[ "$host_arg" == *[[:space:]]* ]]; then
                _ssh_error "Некоректний хост (містить пробіли): $host_arg"
                return 1
            fi
        done
        local hosts=("$@")
    else
        _ssh_require_config || return 1

        local hosts=("${(@f)$(_ssh_config_hosts)}")
    fi

    if ((${#hosts[@]} == 0)); then
        _ssh_warning "Немає підключень для перевірки."
        return 1
    fi

    print
    print -r -- "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH CONNECTIVITY CHECK${SSH_COLOR_RESET}"
    print

    # Паралельна перевірка: кожен хост у фоновому job, тому
    # недоступний сервер не блокує решту на 5 секунд (ConnectTimeout).
    # Фоновий процес не може змінювати змінні оболонки, тому
    # коди виходу зберігаються у тимчасові файли за індексом.
    local tmpdir
    if ! tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/ssh-check.XXXXXXXX"); then
        _ssh_error "Не вдалося створити тимчасовий каталог."
        return 1
    fi

    local index=0
    local -a job_pids

    for host in "${hosts[@]}"; do
        ((index++))
        (
            ssh \
                -o BatchMode=yes \
                -o ConnectTimeout=5 \
                -o ConnectionAttempts=1 \
                -o LogLevel=ERROR \
                "$host" true >/dev/null 2>&1
            printf '%d' $? > "$tmpdir/$index"
        ) &
        job_pids+=($!)
    done

    wait "${job_pids[@]}"

    index=0
    for host in "${hosts[@]}"; do
        ((checked++))
        ((index++))
        printf "  %-22s " "$host"

        exit_code=$(<"$tmpdir/$index")

        if ((exit_code == 0)); then
            print -r -- "${SSH_COLOR_GREEN}PASS${SSH_COLOR_RESET}"
        else
            print -r -- "${SSH_COLOR_RED}FAIL${SSH_COLOR_RESET} ${SSH_COLOR_GRAY}(код: $exit_code)${SSH_COLOR_RESET}"
            ((failed++))
        fi
    done

    rm -rf -- "$tmpdir"

    print
    print "Перевірено: $checked"
    print "Успішно:    $((checked - failed))"
    print "Помилок:    $failed"
    print

    if ((failed == 0)); then
        _ssh_success "Усі SSH-підключення доступні."
        return 0
    else
        _ssh_warning "Є недоступні SSH-підключення."
        return 1
    fi
}

# ============================================================
# 3. SSH-INFO
# Інформація про SSH-ключі
# ============================================================

ssh-info() {
    _ssh_require_client || return 1

    local key
    local fingerprint
    local key_count=0
    local key_locked

    print
    print -r -- "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH KEY INFORMATION${SSH_COLOR_RESET}"
    print

    # --------------------------------------------------------
    # SSH AGENT
    # --------------------------------------------------------

    print -r -- "${SSH_COLOR_BOLD}SSH Agent:${SSH_COLOR_RESET}"

    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
        _ssh_success "SSH Agent доступний."

        print "  Socket: $SSH_AUTH_SOCK"

        ssh-add -l 2>/dev/null
        local agent_status=$?

        if ((agent_status == 1)); then
            _ssh_warning "В агенті немає завантажених ключів."
        elif ((agent_status == 2)); then
            _ssh_error "Не вдалося отримати список ключів."
        fi
    else
        _ssh_error "SSH Agent недоступний."
    fi

    print

    # --------------------------------------------------------
    # ПРИВАТНІ ТА ПУБЛІЧНІ КЛЮЧІ
    # --------------------------------------------------------

    print -r -- "${SSH_COLOR_BOLD}SSH Keys:${SSH_COLOR_RESET}"

    # Приватні ключі: уся ~/.ssh та ~/.ssh/keys.
    # Публічні (*.pub) та службові файли пропускаємо, тож тут
    # потрапляють і id_rsa, id_ecdsa, id_dsa — не лише id_ed25519.

    for key in \
        "$HOME/.ssh/"*(N) \
        "$HOME/.ssh/keys/"*(N); do
        [[ -f "$key" ]] || continue
        [[ "$key" == *.pub ]] && continue

        # Службові файли, які не є приватними ключами.
        case "${key:t}" in
            known_hosts|known_hosts.*|authorized_keys*|config) continue ;;
        esac

        # Перевіряємо, що вміст приватного ключа доступний без
        # розшифрування. -P '' забороняє ssh-keygen запитувати пароль
        # з терміналу: для зашифрованих ключів перевірка одразу
        # завершується помилкою без блокування сеансу.
        key_locked=0
        if ! ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
            if ssh-keygen -lf "$key" >/dev/null 2>&1; then
                # Файл коректний, але захищений парольною фразою.
                key_locked=1
            else
                _ssh_warning "Не вдалося перевірити ключ: ${key:t}"
                continue
            fi
        fi

        # -lf не потребує розшифрування, тож відбиток доступний завжди.
        fingerprint="$(ssh-keygen -lf "$key" 2>/dev/null)"

        print -r -- "  ${SSH_COLOR_GREEN}${key:t}${SSH_COLOR_RESET}"
        print "  $fingerprint"

        if ((key_locked)); then
            _ssh_info "Ключ захищений парольною фразою: перевірку вмісту пропущено."
        fi

        if [[ -f "${key}.pub" ]]; then
            _ssh_success "Публічний ключ існує."
        else
            _ssh_warning "Публічний файл відсутній."
        fi

        ((key_count++))
        print
    done

    if ((key_count == 0)); then
        _ssh_warning "SSH-ключі не знайдені."
    else
        _ssh_success "Перевірено ключів: $key_count"
    fi
}

# ============================================================
# 4. SSH-COPY-KEY
# Копіювання публічного ключа на сервер
# ============================================================

ssh-copy-key() {
    _ssh_require_client || return 1

    if (($# < 1 || $# > 2)); then
        print "Використання:"
        print "  ssh-copy-key <host> [public-key]"
        print
        print "Приклади:"
        print "  ssh-copy-key linux-server"
        print "  ssh-copy-key linux-server ~/.ssh/keys/servers.pub"
        return 1
    fi

    local host="$1"
    local public_key="${2:-$HOME/.ssh/id_ed25519.pub}"

    # Перевірка наявності утиліти ssh-copy-id
    if ! command -v ssh-copy-id >/dev/null 2>&1; then
        _ssh_error "ssh-copy-id не знайдений."
        return 1
    fi

    # Перевірка публічного ключа
    if [[ ! -f "$public_key" ]]; then
        _ssh_error "Публічний ключ не знайдений: $public_key"
        return 1
    fi

    if ! ssh-keygen -lf "$public_key" >/dev/null 2>&1; then
        _ssh_error "Некоректний публічний ключ."
        return 1
    fi

    print
    _ssh_info "Сервер: $host"
    _ssh_info "Ключ: $public_key"
    print

    _ssh_warning "Переконайся, що це звичайний OpenSSH-сервер."
    _ssh_warning "Для MikroTik RouterOS використовуй окремий механізм імпорту ключів."

    # Копіювання ключа.
    # Потрібна авторизація на сервері, якщо ключ ще не встановлений.

    ssh-copy-id -i "$public_key" "$host"
}

# ============================================================
# 5. SSH-AGENT-STATUS
# Стан SSH Agent
# ============================================================

ssh-agent-status() {
    print
    print -r -- "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH AGENT STATUS${SSH_COLOR_RESET}"
    print

    # Перевірка змінної SSH_AUTH_SOCK
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        _ssh_error "SSH_AUTH_SOCK не встановлений."
        return 1
    fi

    # Перевірка Unix Socket
    if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
        _ssh_error "SSH Agent Socket недоступний."
        return 1
    fi

    _ssh_success "SSH Agent працює."

    print "  Socket: $SSH_AUTH_SOCK"

    # Перевірка Keychain
    if command -v keychain >/dev/null 2>&1; then
        _ssh_success "Keychain встановлений."
    else
        _ssh_warning "Keychain не встановлений."
    fi

    print

    # Перевірка завантажених ключів
    local agent_output
    agent_output="$(ssh-add -l 2>&1)"
    local exit_code=$?

    if ((exit_code == 0)); then
        _ssh_success "Завантажені ключі:"
        print -r -- "$agent_output"
        return 0
    elif ((exit_code == 1)); then
        _ssh_warning "SSH Agent працює, але ключів немає."
        return 1
    else
        _ssh_error "Не вдалося отримати стан SSH Agent."
        print -r -- "$agent_output"
        return 1
    fi
}

# ============================================================
# КІНЕЦЬ SSH UTILITIES v1.0
# ============================================================
