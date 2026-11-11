# ============================================================
# Набір команд для керування SSH у Zsh
# ============================================================

# ============================================================
# КОМАНДИ ТА ЇХ ПРИЗНАЧЕННЯ
# ============================================================
#
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
#   Не запускає Agent.
#
# ssh-copy-key <host> [public-key]
#   Копіює публічний SSH-ключ на сервер через ssh-copy-id.
#   Якщо ключ не вказаний, використовує ~/.ssh/id_ed25519.pub.
#
# ssh-agent-status
#
# ssh <host>, scp ..., sftp ...
#   Під час першого виклику автоматично запускає SSH Agent.
#   Перевіряє стан SSH Agent без його запуску:
#   SSH_AUTH_SOCK, Unix Socket та завантажені ключі.
#
# ВІДКЛАДЕНИЙ ЗАПУСК SSH AGENT
#   Agent запускається автоматично лише під час першого реального
#   виклику ssh, scp, sftp, ssh-copy-id або ssh-check.
#   Для звичайного перегляду конфігурації (ssh-list) Agent не потрібен.
#
# ============================================================
# ПРИКЛАДИ ВИКОРИСТАННЯ
# ============================================================
#
# ssh-list
# ssh-check
# ssh-check linux-server mikrotik
# ssh-info
# ssh-copy-key linux-server
# ssh-copy-key linux-server ~/.ssh/keys/servers.pub
# ssh-agent-status
#
# ssh <host>, scp ..., sftp ...
#   Під час першого виклику автоматично запускає SSH Agent.
#
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
# Формат %s захищає текст від інтерпретації форматних специфікаторів.

# Виведення повідомлення про успіх.
_ssh_success() {
    printf '%s\n' "${SSH_COLOR_GREEN}[OK]${SSH_COLOR_RESET} $*"
}

# Виведення попередження.
_ssh_warning() {
    printf '%s\n' "${SSH_COLOR_YELLOW}[WARN]${SSH_COLOR_RESET} $*"
}

# Виведення помилки у stderr.
_ssh_error() {
    printf '%s\n' "${SSH_COLOR_RED}[ERROR]${SSH_COLOR_RESET} $*" >&2
}

# Виведення інформації.
_ssh_info() {
    printf '%s\n' "${SSH_COLOR_CYAN}[INFO]${SSH_COLOR_RESET} $*"
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
# Виключає коментарі, wildcard-шаблони (*, ?) та заперечення (!host).
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
# ВІДКЛАДЕНИЙ ЗАПУСК SSH AGENT
# ============================================================

# Запускає окремий Agent для поточного інтерактивного Zsh-сеансу.
# Сокет розміщується в XDG_RUNTIME_DIR і видаляється під час виходу
# з оболонки. Agent не запускається під час завантаження конфігурації.
_ssh_ensure_agent() {
    local runtime_dir
    local socket
    local agent_output
    local agent_pid
    local agent_status

    # Якщо поточний Agent доступний, повторно його не запускаємо.
    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
        ssh-add -l >/dev/null 2>&1
        agent_status=$?

        # ssh-add повертає 1, якщо Agent доступний, але ключів немає.
        ((agent_status == 0 || agent_status == 1)) && return 0
    fi

    # Для безпечного Unix-сокета потрібен runtime-каталог користувача.
    runtime_dir="${XDG_RUNTIME_DIR:-}"

    if [[ -z "$runtime_dir" || ! -d "$runtime_dir" || ! -w "$runtime_dir" ]]; then
        _ssh_error "XDG_RUNTIME_DIR відсутній або недоступний для запису."
        return 1
    fi

    # Унікальний сокет для поточного Zsh-сеансу.
    socket="${runtime_dir}/ssh-agent-${UID}-$$.sock"

    # Якщо сокет цього сеансу вже існує, перевіряємо його.
    if [[ -S "$socket" ]]; then
        export SSH_AUTH_SOCK="$socket"
        ssh-add -l >/dev/null 2>&1
        agent_status=$?

        if ((agent_status == 0 || agent_status == 1)); then
            return 0
        fi

        unset SSH_AUTH_SOCK
        rm -f -- "$socket"
    elif [[ -e "$socket" ]]; then
        _ssh_error "Шлях сокета зайнятий не Unix-сокетом: $socket"
        return 1
    fi

    # Запускаємо Agent із заздалегідь визначеним шляхом сокета.
    agent_output="$(command ssh-agent -a "$socket" -s 2>/dev/null)" || {
        _ssh_error "Не вдалося запустити SSH Agent."
        return 1
    }

    agent_pid="$(printf '%s\n' "$agent_output" |
        sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p' | head -n 1)"

    if [[ -z "$agent_pid" || ! -S "$socket" ]]; then
        _ssh_error "SSH Agent запущений некоректно: не знайдено PID або сокет."
        return 1
    fi

    export SSH_AUTH_SOCK="$socket"
    export SSH_AGENT_PID="$agent_pid"

    typeset -g _SSH_LAZY_AGENT_SOCKET="$socket"
    typeset -g _SSH_LAZY_AGENT_PID="$agent_pid"
    typeset -g _SSH_LAZY_AGENT_OWNED=1

    # Додаємо cleanup-hook лише один раз.
    typeset -ga zshexit_functions
    if ((${zshexit_functions[(Ie)_ssh_agent_cleanup]} == 0)); then
        zshexit_functions+=(_ssh_agent_cleanup)
    fi

    _ssh_info "SSH Agent запущений за першим запитом."
}

# Завершує лише Agent, створений цим Zsh-сеансом.
# Уже наявний зовнішній Agent ця функція не зупиняє.
_ssh_agent_cleanup() {
    ((${_SSH_LAZY_AGENT_OWNED:-0})) || return 0

    if [[ -n "${_SSH_LAZY_AGENT_PID:-}" ]]; then
        kill "$_SSH_LAZY_AGENT_PID" 2>/dev/null
    fi

    if [[ -n "${_SSH_LAZY_AGENT_SOCKET:-}" ]]; then
        rm -f -- "$_SSH_LAZY_AGENT_SOCKET"
    fi
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

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue

        # Отримуємо ефективну конфігурацію SSH.
        details="$(command ssh -G "$host" 2>/dev/null)"
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
# Паралельна перевірка доступності SSH-серверів
# ============================================================

ssh-check() {
    # Локально вимикаємо повідомлення про фонові процеси Zsh.
    # Після завершення функції налаштування оболонки відновляться.
    setopt localoptions no_monitor no_notify

    _ssh_require_client || return 1
    _ssh_ensure_agent || return 1

    local host
    local exit_code
    local pid
    local checked=0
    local failed=0
    local index=0

    # --------------------------------------------------------
    # ОТРИМАННЯ СПИСКУ ХОСТІВ
    # --------------------------------------------------------

    if (($# > 0)); then
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

    # --------------------------------------------------------
    # ЗАГОЛОВОК
    # --------------------------------------------------------

    printf '\n'
    printf '%s\n' "${SSH_COLOR_BOLD}${SSH_COLOR_CYAN}SSH CONNECTIVITY CHECK${SSH_COLOR_RESET}"
    printf '\n'

    # --------------------------------------------------------
    # ТИМЧАСОВИЙ КАТАЛОГ
    # --------------------------------------------------------

    local tmpdir

    if ! tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/ssh-check.XXXXXXXX"); then
        _ssh_error "Не вдалося створити тимчасовий каталог."
        return 1
    fi

    # --------------------------------------------------------
    # ПАРАЛЕЛЬНИЙ ЗАПУСК ПЕРЕВІРОК
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # ОЧІКУВАННЯ ЗАВЕРШЕННЯ ВСІХ ПРОЦЕСІВ
    # --------------------------------------------------------

    for pid in "${job_pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # --------------------------------------------------------
    # ВИВЕДЕННЯ РЕЗУЛЬТАТІВ
    # --------------------------------------------------------

    index=0

    for host in "${hosts[@]}"; do
        ((checked++))
        ((index++))

        printf '  %-22s ' "$host"

        if [[ -f "$tmpdir/$index" ]]; then
            exit_code=$(<"$tmpdir/$index")
        else
            exit_code=255
        fi

        if [[ "$exit_code" == 0 ]]; then
            printf '%s\n' "${SSH_COLOR_GREEN}PASS${SSH_COLOR_RESET}"
        else
            printf '%s\n' \
                "${SSH_COLOR_RED}FAIL${SSH_COLOR_RESET} ${SSH_COLOR_GRAY}(код: $exit_code)${SSH_COLOR_RESET}"

            ((failed++))
        fi
    done

    # --------------------------------------------------------
    # ОЧИЩЕННЯ
    # --------------------------------------------------------

    rm -rf -- "$tmpdir"

    # --------------------------------------------------------
    # ПІДСУМКИ
    # --------------------------------------------------------

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
        _ssh_info "SSH Agent ще не запущений. Він стартує під час першого SSH-виклику."
    fi

    printf '\n'

    # --------------------------------------------------------
    # ПРИВАТНІ ТА ПУБЛІЧНІ КЛЮЧІ
    # --------------------------------------------------------

    printf '%s\n' "${SSH_COLOR_BOLD}SSH Keys:${SSH_COLOR_RESET}"

    # Перевіряємо приватні ключі у ~/.ssh та ~/.ssh/keys.
    # Публічні та службові файли пропускаємо.

    for key in \
        ${HOME}/.ssh/*(N) \
        ${HOME}/.ssh/keys/*(N); do

        [[ -f "$key" ]] || continue
        [[ "$key" == *.pub ]] && continue

        case "${key:t}" in
            known_hosts | known_hosts.* | authorized_keys* | config) continue ;;
        esac

        # Перевірка ключа без запиту парольної фрази.
        key_locked=0

        if ! ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
            if ssh-keygen -lf "$key" >/dev/null 2>&1; then
                key_locked=1
            else
                _ssh_warning "Не вдалося перевірити ключ: ${key:t}"
                continue
            fi
        fi

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

    # Перевірка наявності ssh-copy-id.
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

    # Запускаємо Agent лише перед фактичним мережевим підключенням.
    _ssh_ensure_agent || return 1

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

    # Команда лише перевіряє стан і ніколи не запускає Agent.
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        _ssh_info "SSH Agent ще не запускався. Це нормальний стан до першого SSH-виклику."
        return 0
    fi

    if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
        _ssh_warning "SSH_AUTH_SOCK встановлений, але сокет недоступний."
        printf '  Socket: %s\n' "$SSH_AUTH_SOCK"
        return 1
    fi

    _ssh_success "SSH Agent працює."
    printf '  Socket: %s\n' "$SSH_AUTH_SOCK"

    if [[ -n "${SSH_AGENT_PID:-}" ]]; then
        printf '  PID:    %s\n' "$SSH_AGENT_PID"
    fi

    printf '\n'

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
        return 0
    else
        _ssh_error "Не вдалося отримати стан SSH Agent."
        printf '%s\n' "$agent_output"
        return 1
    fi
}

# ============================================================
# ОБГОРТКИ SSH-КОМАНД
# ============================================================

# Перехоплюємо інтерактивні виклики, щоб запускати Agent ліниво.
# Внутрішній command обходить функцію та запускає системний бінарний файл.
ssh() {
    _ssh_ensure_agent || return 1
    command ssh "$@"
}

scp() {
    _ssh_ensure_agent || return 1
    command scp "$@"
}

sftp() {
    _ssh_ensure_agent || return 1
    command sftp "$@"
}

ssh-copy-id() {
    _ssh_ensure_agent || return 1
    command ssh-copy-id "$@"
}
