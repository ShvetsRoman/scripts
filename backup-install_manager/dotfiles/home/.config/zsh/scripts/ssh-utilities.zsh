# ============================================================
# КОМАНДИ ТА ЇХ ПРИЗНАЧЕННЯ
# ============================================================
# ssh-list
#   Показує список налаштованих SSH-підключень:
#   Host, HostName, User, Port.
#
# ssh-check [host ...]
#   Перевіряє доступність SSH-серверів.
#   Без аргументів перевіряє всі хости з ~/.ssh/config.
#   З аргументами перевіряє лише вказані хости.
#
# ssh-info
#   Показує інформацію про SSH Agent та ключі:
#   стан агента, відбитки ключів, наявність .pub файлів.
#
# ssh-copy-key <host> [public-key]
#   Копіює публічний SSH-ключ на сервер через ssh-copy-id.
#   Якщо ключ не вказаний, використовує ~/.ssh/id_ed25519.pub.
#
# ssh-agent-status
#   Перевіряє стан SSH Agent:
#   SSH_AUTH_SOCK, Unix Socket, Keychain та завантажені ключі.
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
# Усі повідомлення виводимо через printf.
# Формат %s запобігає інтерпретації спеціальних символів
# та форматних специфікаторів у тексті користувача.
# Виведення повідомлення про успіх.
_ssh_success() {
    printf '%s\n' "${SSH_COLOR_GREEN}✔${SSH_COLOR_RESET} $*"
}

# Виведення попередження.
_ssh_warning() {
    printf '%s\n' "${SSH_COLOR_YELLOW}⚠${SSH_COLOR_RESET} $*"
}

# Виведення помилки у stderr.
_ssh_error() {
    printf '%s\n' "${SSH_COLOR_RED}✘${SSH_COLOR_RESET} $*" >&2
}

# Виведення інформації.
_ssh_info() {
    printf '%s\n' "${SSH_COLOR_CYAN}ℹ${SSH_COLOR_RESET} $*"
}

# Перевірка наявності SSH-клієнта.
_ssh_require_client() {
    if ! command -v ssh >/dev/null 2>&1; then
        _ssh_error "SSH-клієнт не встановлений."
        return 1
    fi
}

# Перевірка наявності конфігурації.
_ssh_require_config() {
    if [[ ! -f "$HOME/.ssh/config" ]]; then
        _ssh_error "Файл ~/.ssh/config не знайдений."
        return 1
    fi
}

# Витягує імена хостів із ~/.ssh/config.
# Спільна логіка для ssh-list та ssh-check:
# виключає коментарі, wildcard-шаблони (*, ?) та заперечення (!host).
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

    printf '\n'
    printf '%s\n' "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH CONNECTIONS${SSH_COLOR_RESET}"
    printf '%s\n' "${SSH_COLOR_GRAY}Налаштовані SSH-підключення${SSH_COLOR_RESET}"
    printf '\n'

    # Отримуємо назви Host з конфігурації.
    # Виключаємо шаблони та wildcard-записи.

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        # ssh -G повертає ефективну конфігурацію для хоста.
        # Він не перевіряє доступність, тому аналізуємо результат.
        details="$(ssh -G "$host" 2>/dev/null)"
        [[ -n "$details" ]] || continue

        hostname="$(printf '%s\n' "$details" |
            awk '$1 == "hostname" {print $2; exit}')"

        username="$(printf '%s\n' "$details" |
            awk '$1 == "user" {print $2; exit}')"

        port="$(printf '%s\n' "$details" |
            awk '$1 == "port" {print $2; exit}')"

        printf '  %s%-20s%s %s\n' \
            "$SSH_COLOR_GREEN" "$host" "$SSH_COLOR_RESET" "$hostname"

        printf '  %s%-20s%s %s\n' \
            "$SSH_COLOR_GRAY" "User:" "$SSH_COLOR_RESET" "$username"

        printf '  %s%-20s%s %s\n' \
            "$SSH_COLOR_GRAY" "Port:" "$SSH_COLOR_RESET" "$port"

        printf '\n'
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
        # Кожен аргумент — окремий хост.
        # Пробіли у destination для ssh некоректні,
        # тому відхиляємо їх одразу.

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

    printf '\n'
    printf '%s\n' "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH CONNECTIVITY CHECK${SSH_COLOR_RESET}"
    printf '\n'

    # Паралельна перевірка: кожен хост у фоновому job.
    # Недоступний сервер не блокує решту на 5 секунд.
    #
    # Коди виходу зберігаються у тимчасові файли за індексом,
    # оскільки фоновий процес не може змінювати змінні оболонки.

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

            printf '%d' "$?" >"$tmpdir/$index"
        ) &

        job_pids+=($!)
    done

    wait "${job_pids[@]}"

    index=0

    for host in "${hosts[@]}"; do
        ((checked++))
        ((index++))

        printf '  %-22s ' "$host"

        exit_code=$(<"$tmpdir/$index")

        if ((exit_code == 0)); then
            printf '%s\n' "${SSH_COLOR_GREEN}PASS${SSH_COLOR_RESET}"
        else
            printf '%s\n' \
                "${SSH_COLOR_RED}FAIL${SSH_COLOR_RESET} ${SSH_COLOR_GRAY}(код: $exit_code)${SSH_COLOR_RESET}"

            ((failed++))
        fi
    done

    rm -rf -- "$tmpdir"

    printf '\n'
    printf 'Перевірено: %d\n' "$checked"
    printf 'Успішно:    %d\n' "$((checked - failed))"
    printf 'Помилок:    %d\n' "$failed"
    printf '\n'

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

    printf '\n'
    printf '%s\n' "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH KEY INFORMATION${SSH_COLOR_RESET}"
    printf '\n'

    # --------------------------------------------------------
    # SSH AGENT
    # --------------------------------------------------------

    printf '%s\n' "${SSH_COLOR_BOLD}SSH Agent:${SSH_COLOR_RESET}"

    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
        _ssh_success "SSH Agent доступний."

        printf '  Socket: %s\n' "$SSH_AUTH_SOCK"

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

    printf '\n'

    # --------------------------------------------------------
    # ПРИВАТНІ ТА ПУБЛІЧНІ КЛЮЧІ
    # --------------------------------------------------------

    printf '%s\n' "${SSH_COLOR_BOLD}SSH Keys:${SSH_COLOR_RESET}"

    # Приватні ключі: уся ~/.ssh та ~/.ssh/keys.
    # Публічні (*.pub) та службові файли пропускаємо.

    for key in ${HOME}/.ssh/*(N) ${HOME}/.ssh/keys/*(N); do

        [[ -f "$key" ]] || continue
        [[ "$key" == *.pub ]] && continue

        # Службові файли, які не є приватними ключами.
        case "${key:t}" in
            known_hosts | known_hosts.* | authorized_keys* | config) continue ;;
        esac

        # Перевіряємо доступність вмісту приватного ключа
        # без запиту парольної фрази.

        key_locked=0

        if ! ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
            if ssh-keygen -lf "$key" >/dev/null 2>&1; then
                key_locked=1
            else
                _ssh_warning "Не вдалося перевірити ключ: ${key:t}"
                continue
            fi
        fi

        # Відбиток доступний навіть для зашифрованого ключа.
        fingerprint="$(ssh-keygen -lf "$key" 2>/dev/null)"

        printf '  %s%s%s\n' \
            "$SSH_COLOR_GREEN" "${key:t}" "$SSH_COLOR_RESET"

        printf '  %s\n' "$fingerprint"

        if ((key_locked)); then
            _ssh_info "Ключ захищений парольною фразою: перевірку вмісту пропущено."
        fi

        if [[ -f "${key}.pub" ]]; then
            _ssh_success "Публічний ключ існує."
        else
            _ssh_warning "Публічний файл відсутній."
        fi

        ((key_count++))
        printf '\n'
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
        printf '%s\n' "Використання:"
        printf '%s\n' "  ssh-copy-key <host> [public-key]"
        printf '\n'
        printf '%s\n' "Приклади:"
        printf '%s\n' "  ssh-copy-key linux-server"
        printf '%s\n' "  ssh-copy-key linux-server ~/.ssh/keys/servers.pub"

        return 1
    fi

    local host="$1"
    local public_key="${2:-$HOME/.ssh/id_ed25519.pub}"

    # Перевірка наявності утиліти ssh-copy-id.
    if ! command -v ssh-copy-id >/dev/null 2>&1; then
        _ssh_error "ssh-copy-id не знайдений."
        return 1
    fi

    # Перевірка публічного ключа.
    if [[ ! -f "$public_key" ]]; then
        _ssh_error "Публічний ключ не знайдений: $public_key"
        return 1
    fi

    if ! ssh-keygen -lf "$public_key" >/dev/null 2>&1; then
        _ssh_error "Некоректний публічний ключ."
        return 1
    fi

    printf '\n'
    _ssh_info "Сервер: $host"
    _ssh_info "Ключ: $public_key"
    printf '\n'

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
    printf '\n'
    printf '%s\n' "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH AGENT STATUS${SSH_COLOR_RESET}"
    printf '\n'

    # Перевірка змінної SSH_AUTH_SOCK.
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        _ssh_error "SSH_AUTH_SOCK не встановлений."
        return 1
    fi

    # Перевірка Unix Socket.
    if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
        _ssh_error "SSH Agent Socket недоступний."
        return 1
    fi

    _ssh_success "SSH Agent працює."

    printf '  Socket: %s\n' "$SSH_AUTH_SOCK"

    # Перевірка Keychain.
    if command -v keychain >/dev/null 2>&1; then
        _ssh_success "Keychain встановлений."
    else
        _ssh_warning "Keychain не встановлений."
    fi

    printf '\n'

    # Перевірка завантажених ключів.
    local agent_output
    local exit_code

    agent_output="$(ssh-add -l 2>&1)"
    exit_code=$?

    if ((exit_code == 0)); then
        _ssh_success "Завантажені ключі:"
        printf '%s\n' "$agent_output"
        return 0
    elif ((exit_code == 1)); then
        _ssh_warning "SSH Agent працює, але ключів немає."
        return 1
    else
        _ssh_error "Не вдалося отримати стан SSH Agent."
        printf '%s\n' "$agent_output"
        return 1
    fi
}
