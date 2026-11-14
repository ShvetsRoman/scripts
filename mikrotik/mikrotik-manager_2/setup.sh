#!/usr/bin/env bash
# =============================================================================
# setup.sh — завантаження конфігурації на роутер MikroTik
#
# Використання:
#   ./setup.sh --name hap-ac             # ТІЛЬКИ завантажує config.rsc на роутер
#   ./setup.sh --name hap-ac --reset     # завантажує файл і робить reset
#                                        # no-defaults з run-after-reset=config.rsc
#
# Налаштування підключення скрипт бере з файлу routers/<name>/config.rsc
# (рядки виду ":global routerHost ...").
#
# Опції:
#   --name <ім'я>   Обов'язково. Ім'я роутера = каталог у routers/
#   --reset         Після завантаження виконати скидання конфігурації
#                   (no-defaults) з автоматичним запуском config.rsc.
#                   УВАГА: деструктивна операція, вимагає підтвердження.
#   --yes, -y       Не запитувати підтвердження (для автоматизації)
#   --dry-run       Показати команди, нічого не виконувати
#   --key <шлях>    SSH-ключ (або змінна середовища SSH_KEY).
#                   Якщо ключ не задано — пароль через sshpass.
#   --insecure-host-key  Не перевіряти host key SSH (ризик MITM; лише лабораторія)
#   --help, -h      Довідка
#
# Поведінка:
#   SSH: усі дії одного запуску йдуть через ОДНУ мультиплексовану сесію
#        (ControlPersist = 10 хв). Якщо підключення не встановилося —
#        [FAIL] і зупинка; якщо передача через сесію не пішла — автоматичний
#        повтор без мультиплексування.
#   без --reset: файл завантажується на роутер і ВСЕ. Застосувати можна
#                вручну на роутері:  /import file-name=config.rsc
#   з --reset:   файл завантажується, потім роутер скидається до чистого
#                стану і ПІСЛЯ перезавантаження сам імпортує config.rsc
#                (run-after-reset). Це єдиний надійний спосіб, бо після
#                no-defaults-reset SSH-адреси попередньої конфігурації
#                зникають.
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Кольоровий вивід (вимикається, якщо stdout не термінал)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'
    C_ERR=$'\033[1;31m';  C_OFF=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi

info()  { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
err()   { printf '%s[FAIL]%s %s\n' "$C_ERR"  "$C_OFF" "$*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

# -----------------------------------------------------------------------------
# Розбір аргументів
# -----------------------------------------------------------------------------
NAME=""
DO_RESET=0
ASSUME_YES=0
DRY_RUN=0
SSH_KEY="${SSH_KEY:-}"
INSECURE_HOST_KEY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)    [[ -n "${2:-}" ]] || die "--name: потрібно вказати ім'я роутера"
                   NAME="$2"; shift 2 ;;
        --reset)   DO_RESET=1; shift ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --key)     [[ -n "${2:-}" ]] || die "--key: потрібно вказати шлях до ключа"
                   SSH_KEY="$2"; shift 2 ;;
        --insecure-host-key) INSECURE_HOST_KEY=1; shift ;;
        --help|-h) usage ;;
        *)         die "Невідома опція: $1 (див. ./setup.sh --help)" ;;
    esac
done

[[ -n "$NAME" ]] || die "Не вказано --name (див. ./setup.sh --help)"

# Ім'я роутера = каталог у routers/: лише малі латинські літери, цифри
# та дефіс. Відсікає шляхи на кшталт "../x" та порожні/дивні імена.
[[ $NAME =~ ^[a-z0-9-]+$ ]] || die "--name: дозволені лише малі латинські літери, цифри та дефіс"

# -----------------------------------------------------------------------------
# Шляхи та перевірки залежностей
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/routers/$NAME/config.rsc"

[[ -f "$CONFIG" ]] || {
    err "Файл не знайдено: $CONFIG"
    err "Доступні роутери:"
    find "$SCRIPT_DIR/routers" -mindepth 2 -maxdepth 2 -name config.rsc 2>/dev/null \
        | sed "s|$SCRIPT_DIR/routers/||; s|/config.rsc||" \
        | sed 's/^/         - /' >&2 || true
    exit 1
}

command -v ssh  >/dev/null || die "ssh не знайдено у PATH"
command -v scp  >/dev/null || die "scp не знайдено у PATH"

# -----------------------------------------------------------------------------
# Розбір змінних з config.rsc
# Підтримуються рядки виду:  :global NAME "значення"   або   :global NAME 10
# Значення беруться з НАЧАЛЬНИХ :global-рядків — саме такий формат читає
# RouterOS під час імпорту, тому parsing завжди узгоджений із конфігом.
# -----------------------------------------------------------------------------
declare -A VARS

parse_globals() {
    local file="$1"
    local line name value
    local regex='^:global[[:space:]]+([A-Za-z][A-Za-z0-9]*)[[:space:]]+(.+)$'

    # Пропускаємо коментарні рядки та вирівнюємо відступи
    while IFS= read -r line; do
        line="${line%"${line##*[![:space:]]}"}"   # обрізати завершальні пробіли
        [[ $line =~ $regex ]] || continue
        name="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%$'\r'}"
        # Прибрати обгортаючі подвійні лапки, якщо є
        if [[ ${#value} -ge 2 && $value == \"* && $value == *\" ]]; then
            value="${value:1:${#value}-2}"
        fi
        VARS["$name"]="$value"
    done < <(grep -v '^[[:space:]]*#' "$file")
}

parse_globals "$CONFIG"

# Допоміжний доступ зі значенням за замовчуванням
var()   { printf '%s' "${VARS[$1]:-}"; }
var_or() { printf '%s' "${VARS[$1]:-$2}"; }

# -----------------------------------------------------------------------------
# Перевірка обов'язкових змінних підключення
# -----------------------------------------------------------------------------
HOST="$(var routerHost)"
USER_NAME="$(var routerUser)"
PASSWORD="$(var routerPassword)"
SSH_PORT="$(var_or routerSshPort 22)"
FILE_NAME="$(var_or configFile config.rsc)"

[[ -n "$HOST" ]]      || die "У config.rsc не задано :global routerHost"
[[ -n "$USER_NAME" ]] || die "У config.rsc не задано :global routerUser"

# Попередження про незаповнені плейсхолдери (ЗАМІНІТЬ_*).
# Показуються лише ті, що стосуються УВІМКНЕНИХ функцій: якщо тумблер false,
# відповідний пароль на роутері ніде не застосується — WARN не виводиться.
# adminPassword перевіряється завжди (не залежить від тумблерів).
PLACEHOLDER_MSGS=()

is_on() { [[ "$(var "$1")" == "true" ]]; }

add_ph() {   # $1 = ім'я змінної, $2 = пояснення
    local v
    v="$(var "$1")"
    if [[ "$v" == ЗАМІНІТЬ* ]]; then
        PLACEHOLDER_MSGS+=("    $1 = $v  ($2)")
    fi
}

add_ph adminPassword "пароль адміністратора — заповнювати завжди"

WIFI_ON=0
is_on enableWifi2Ghz && WIFI_ON=1
is_on enableWifi5Ghz && WIFI_ON=1
(( WIFI_ON ))        && add_ph wifiPassword "пароль WiFi (радіо увімкнене)"
is_on enableGuest     && add_ph guestPassword "пароль гостьової мережі"
is_on enableIot       && add_ph iotPassword "пароль мережі IoT"
is_on enableWireguard && add_ph wgPeerKey "публічний ключ WireGuard-піра"

if (( ${#PLACEHOLDER_MSGS[@]} )); then
    warn "У config.rsc є незаповнені плейсхолдери (увімкнені функції):"
    for m in "${PLACEHOLDER_MSGS[@]}"; do warn "$m"; done
    warn "Конфіг застосується з паролями-плейсхолдерами! Виправте перед reset."
fi

# -----------------------------------------------------------------------------
# Автентифікація: SSH-ключ у пріоритеті, інакше пароль через sshpass
# -----------------------------------------------------------------------------
# Мультиплексування: усі ssh/scp у межах одного запуску йдуть через ОДНУ
# SSH-сесію (master), яка живе 10 хв (ControlPersist) — без повторної
# автентифікації. Якщо сервер не підтримує кілька каналів в одній сесії,
# скрипт автоматично повторює передачу без мультиплексування.
#
# ControlPath — у приватному каталозі mktemp: прогнозований спільний шлях
# у /tmp дозволяв іншому локальному користувачу зайняти сокет заздалегідь.
MUX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssh-mux-mikrotik.XXXXXX")"
trap '[[ -n "${MUX_DIR:-}" ]] && rm -rf -- "$MUX_DIR"' EXIT

HOSTKEY_OPTS=(-o StrictHostKeyChecking=accept-new)
if (( INSECURE_HOST_KEY )); then
    # Вимкнення перевірки host key — лише за явним прапорцем: інакше
    # MITM у LAN перехоплював би пароль адміністратора непомітно.
    warn "strict host key checking вимкнено (--insecure-host-key): ризик MITM, лише для контрольованої лабораторії"
    HOSTKEY_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null)
fi

SSH_OPTS=("${HOSTKEY_OPTS[@]}" -o LogLevel=ERROR -p "$SSH_PORT"
          -o ConnectTimeout=10
          -o ControlMaster=auto
          -o ControlPath="$MUX_DIR/ctl-%r@%h-%p"
          -o ControlPersist=10m)
SSH_NOMUX=("${SSH_OPTS[@]}" -o ControlMaster=no -o ControlPath=none)

if [[ -n "$SSH_KEY" ]]; then
    [[ -f "$SSH_KEY" ]] || die "SSH-ключ не знайдено: $SSH_KEY"
    AUTH_MODE="key"
    SSH_OPTS+=(-i "$SSH_KEY" -o PasswordAuthentication=no -o IdentitiesOnly=yes)
    info "Автентифікація: SSH-ключ ($SSH_KEY)"
elif (( DRY_RUN )); then
    # У dry-run підключення не виконується — пароль/sshpass не потрібні
    AUTH_MODE="password"
    info "Автентифікація (dry-run): як у конфігу"
else
    command -v sshpass >/dev/null \
        || die "Потрібен sshpass для автентифікації за паролем.
         Встановіть його (apt install sshpass) або передайте --key <шлях>."
    [[ -n "$PASSWORD" ]] || die "Не задано routerPassword у config.rsc (потрібен для SSH)"
    AUTH_MODE="password"
    info "Автентифікація: пароль (sshpass)"
fi

# Конструкції команд з урахуванням способу автентифікації
# scp позначає порт як -P (ssh — -p); заміна поелементно, масив НЕ колапсує
# в один аргумент (це і була причина помилки "keyword stricthostkeychecking")
SCP_OPTS=("${SSH_OPTS[@]/-p/-P}")
SCP_NOMUX=("${SSH_NOMUX[@]/-p/-P}")
MUX=1   # 1 = використовувати мультиплексовану сесію

ssh_cmd() {
    local opts
    if (( MUX )); then opts=("${SSH_OPTS[@]}"); else opts=("${SSH_NOMUX[@]}"); fi
    if [[ "$AUTH_MODE" == "password" ]]; then
        # Пароль передається через середовище (SSHPASS), а не в argv процесу:
        # "sshpass -p" залишав пароль адміністратора видимим у ps//proc/*/cmdline.
        SSHPASS="$PASSWORD" sshpass -e ssh "${opts[@]}" "$USER_NAME@$HOST" "$@"
    else
        ssh "${opts[@]}" "$USER_NAME@$HOST" "$@"
    fi
}

scp_cmd() {
    local opts
    if (( MUX )); then opts=("${SCP_OPTS[@]}"); else opts=("${SCP_NOMUX[@]}"); fi
    if [[ "$AUTH_MODE" == "password" ]]; then
        SSHPASS="$PASSWORD" sshpass -e scp "${opts[@]}" "$1" "$2"
    else
        scp "${opts[@]}" "$1" "$2"
    fi
}

# Закрити master-сесію (не фатально, якщо її вже немає)
ssh_close_master() {
    ssh -O exit -p "$SSH_PORT" \
        -o ControlPath="$MUX_DIR/ctl-%r@%h-%p" \
        "$USER_NAME@$HOST" >/dev/null 2>&1 || true
}

# Обгортка для dry-run: показує, але не виконує
run() {
    if (( DRY_RUN )); then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------------
# Перевірка досяжності хоста (не блокує — ICMP може бути заборонений)
# -----------------------------------------------------------------------------
if (( ! DRY_RUN )); then
    if ping -c 1 -W 2 "$HOST" >/dev/null 2>&1; then
        ok "Хост $HOST досяжний (ICMP)"
    else
        warn "Хост $HOST не відповідає на ICMP (можливо, заборонений ping) — продовжуємо"
    fi
fi

# -----------------------------------------------------------------------------
# Підсумок
# -----------------------------------------------------------------------------
info "Роутер:        $NAME"
info "Конфіг:        $CONFIG"
info "Хост:          $HOST:$SSH_PORT"
info "Користувач:    $USER_NAME"
info "Файл на роутері: $FILE_NAME"
if (( DO_RESET )); then
    info "Режим:         завантажити + reset no-defaults + автозапуск конфіга"
else
    info "Режим:         ТІЛЬКИ завантаження файлу (без імпорту)"
fi

# -----------------------------------------------------------------------------
# Підтвердження перед reset (деструктивна операція)
# -----------------------------------------------------------------------------
if (( DO_RESET && ! ASSUME_YES && ! DRY_RUN )); then
    warn "RESET видалить УСЮ поточну конфігурацію роутера $HOST!"
    read -r -p "Продовжити? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Скасовано користувачем"
fi

# -----------------------------------------------------------------------------
# Перевірка підключення: створює master-сесію заздалегідь. Без підключення
# подальші кроки безглузді — зупиняємось з явним діагностичним повідомленням.
# -----------------------------------------------------------------------------
if (( ! DRY_RUN )); then
    if ssh_cmd ":put connected" >/dev/null 2>&1; then
        ok "SSH-підключення встановлено (одна мультиплексована сесія, живе 10 хв)"
    else
        ssh_close_master
        err "Підключення не відбулося: $USER_NAME@$HOST:$SSH_PORT"
        err "Перевірте, чи запущена VM/роутер, адресу, порт і пароль."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Завантаження файлу на роутер (SFTP через scp)
# -----------------------------------------------------------------------------
info "Завантаження $CONFIG → $HOST:/$FILE_NAME ..."
scp_uploaded=0
if run scp_cmd "$CONFIG" "$USER_NAME@$HOST:/$FILE_NAME"; then
    scp_uploaded=1
elif (( MUX )); then
    # Сервер може не підтримувати кілька каналів в одній сесії — повтор без mux
    warn "Передача через мультиплексовану сесію не вдалася — повтор без мультиплексування"
    MUX=0
    ssh_close_master
    if run scp_cmd "$CONFIG" "$USER_NAME@$HOST:/$FILE_NAME"; then
        scp_uploaded=1
    fi
fi
if (( scp_uploaded )); then
    ok "Файл завантажено"
else
    err "Завантаження файлу не вдалося (перевірте доступ і пароль)."
    exit 1
fi

# -----------------------------------------------------------------------------
# Reset (якщо запитано)
# -----------------------------------------------------------------------------
if (( DO_RESET )); then
    info "Виконання: /system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=$FILE_NAME"
    # RouterOS запитує підтвердження "Dangerous! Reset anyway? [y/N]" — подаємо 'y'
    if (( DRY_RUN )); then
        info "[dry-run] printf 'y\\n' | ssh ... \"/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=$FILE_NAME\""
    else
        printf 'y\n' | ssh_cmd "/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=$FILE_NAME" \
            || warn "SSH-сесія завершилася з помилкою (роутер перезавантажується — це очікувано)"
    fi
    ok "Команду reset надіслано. Роутер перезавантажується..."
    info "Після перезавантаження роутер САМ застосує config.rsc (run-after-reset)."
    info "Орієнтовний час: 2–3 хвилини."
else
    info "Файл завантажено. Застосувати вручну на роутері:"
    info "    /import file-name=$FILE_NAME"
    info "Або запустіть: ./setup.sh --name $NAME --reset"
fi

ok "Готово"
