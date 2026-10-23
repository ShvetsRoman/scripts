#!/usr/bin/env bash

# Час виконання у кожному рядку (HH:MM:SS) — зручно розбирати логи довгих синхронізацій.
_ts() { printf '%(%H:%M:%S)T' -1; }

log_info()  { printf '%s %s[INFO]%s %s\n'  "$(_ts)" "$C_BLUE"   "$C_RESET" "$*"; }
log_ok()    { printf '%s %s[ OK ]%s %s\n'  "$(_ts)" "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '%s %s[WARN]%s %s\n'  "$(_ts)" "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_title() { printf '\n%s── %s ──%s\n' "$C_CYAN" "$*" "$C_RESET"; }

# Фатальна помилка: повідомлення + завершення скрипта з кодом EX_FAIL.
# (Раніше називалась log_error, але насправді завершувала роботу — ім'я вводило в оману.)
die() {
    printf '%s %s[ERROR]%s %s\n' "$(_ts)" "$C_RED" "$C_RESET" "$*" >&2
    exit "$EX_FAIL"
}

# ERR-trap: жодна неочікувана помилка не завершує скрипт мовчки.
on_err() {
    local rc="$1" line="$2" cmd="$3"

    # У підоболонках ($(...), конвеєри) помилку покаже батьківський процес.
    [[ "$BASHPID" == "$$" ]] || return 0

    printf '%s %s[ERROR]%s Неочікувана помилка (код %s) у %s(), рядок %s: %s\n' \
        "$(_ts)" "$C_RED" "$C_RESET" "$rc" "${FUNCNAME[1]:-main}" "$line" "$cmd" >&2
}

init_logging() {
    # LOG_DIR уже створено в init_runtime (з umask 077). Логи містять імена ваших файлів,
    # тому файл логу створюємо з правами 600.

    printf -v TIMESTAMP '%(%Y-%m-%d_%H-%M-%S)T' -1
    LOG_FILE="$LOG_DIR/backup-sync_${TIMESTAMP}.log"
    ( umask 077; : >>"$LOG_FILE" )

    exec 3>&1 4>&2

    # tee має пережити Ctrl-C/TERM довше за скрипт: інакше фінальні повідомлення губляться,
    # а скрипт гине від SIGPIPE (код 141/-13) замість 130/143.
    # Надійно це дає лише ізоляція: tee запускається у власній сесії (setsid), тож сигнали,
    # надіслані групі процесів скрипта (Ctrl-C, kill -INT -pgid), до нього не доходять.
    # Покладатися лише на `trap '' INT; exec tee` не можна: успадкування ігнорування сигналів
    # через exec відрізняється між версіями bash (у деяких SIGINT повертається до типової поведінки).
    local tee_cmd=(tee -a "$LOG_FILE")
    # BACKUP_SYNC_NO_SETSID=1 примусово вмикає запасний режим (без ізоляції) — напр., якщо setsid
    # на системі поводиться нестандартно.
    if [[ -z "${BACKUP_SYNC_NO_SETSID:-}" ]] && command -v setsid >/dev/null 2>&1; then
        tee_cmd=(setsid "${tee_cmd[@]}")
        TEE_ISOLATED=true
    else
        # Запасний режим без setsid: tee може загинути разом зі скриптом. Тоді будь-який запис у його
        # pipe (навіть службове повідомлення bash «Terminated») вбивав би скрипт — ігноруємо SIGPIPE;
        # а в on_signal ми відключаємось від tee безумовно (див. нижче).
        trap '' PIPE
    fi
    exec > >(trap '' INT TERM; exec "${tee_cmd[@]}") 2>&1
    TEE_PID=$!

    trap on_exit EXIT
    trap 'on_signal INT 130' INT
    trap 'on_signal TERM 143' TERM

    START_EPOCH=$(date +%s)
}

# Повертає stdout/stderr з pipe на оригінальні (консоль). Далі повідомлення йдуть лише в консоль.
detach_tee() {
    [[ "$TEE_DETACHED" == false ]] || return 0
    TEE_DETACHED=true
    exec 1>&3 2>&4 || true
}

# Якщо tee уже не працює (його вбито ззовні), запис у pipe вбив би САМ скрипт через SIGPIPE.
detach_dead_tee() {
    [[ -n "$TEE_PID" && "$TEE_DETACHED" == false ]] || return 0

    if ! kill -0 "$TEE_PID" 2>/dev/null; then
        detach_tee
        log_warn "tee (запис логу) завершився раніше за скрипт: далі вивід лише в консоль, лог-файл неповний."
    fi
}

on_signal() {
    local signal="$1"
    local rc="$2"
    local msg="Отримано сигнал $signal. Завершення роботи."

    if [[ "$TEE_ISOLATED" == true ]]; then
        # tee ізольовано і працює: пишемо звичайним шляхом (порядок рядків у лозі зберігається).
        detach_dead_tee
        log_warn "$msg"
    else
        # Без ізоляції tee міг загинути від того самого сигналу, а перевірка «чи живий» — це гонка
        # (він може померти між перевіркою і записом). Тому відключаємось БЕЗУМОВНО, пишемо в консоль
        # і дописуємо підсумок у лог-файл напряму.
        detach_tee
        log_warn "$msg"
        printf '%s [WARN] %s\n' "$(_ts)" "$msg" >>"$LOG_FILE" || true
    fi

    exit "$rc"
}

on_exit() {
    local rc=$?
    local f

    # `return "$rc"` нижче — ненульовий статус у EXIT-trap, який інакше хибно спрацював би як ERR.
    trap - ERR
    detach_dead_tee

    if ((${#TMP_FILES[@]} > 0)); then
        for f in "${TMP_FILES[@]}"; do
            rm -f -- "$f" || true
        done
    fi

    if ((${#TMP_DIRS[@]} > 0)); then
        for f in "${TMP_DIRS[@]}"; do
            rmdir -- "$f" 2>/dev/null || true
        done
    fi

    release_remote_lock || true

    if [[ -n "${LOG_DIR:-}" && -d "${LOG_DIR:-}" ]]; then
        cleanup_files_older_than "$LOG_DIR" 'backup-sync_*.log' "$KEEP_LOG_DAYS" >/dev/null 2>&1 || true
    fi

    exec 1>&3 2>&4 || true
    exec 3>&- 4>&- || true

    # Чекаємо саме tee, і лише тоді чистимо лог (інакше можна втратити хвіст).
    if [[ -n "$TEE_PID" ]]; then
        wait "$TEE_PID" 2>/dev/null || true
    fi
    sanitize_log || true

    return "$rc"
}

# У лог-файлі не має бути ANSI-кольорів та проміжних станів прогресу rsync (\r).
sanitize_log() {
    local tmp

    [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]] || return 0
    tmp=$(mktemp) || return 0

    if sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' -e 's/.*\r//' "$LOG_FILE" >"$tmp"; then
        cat -- "$tmp" >"$LOG_FILE" || true
    fi
    rm -f -- "$tmp"
}
