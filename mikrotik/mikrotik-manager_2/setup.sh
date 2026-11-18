#!/usr/bin/env bash
# =============================================================================
# setup.sh — безпечне завантаження конфігурації на MikroTik
# =============================================================================
set -Eeuo pipefail

if [[ -t 1 ]]; then
    C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OFF=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi
info(){ printf '%s[INFO]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok(){ printf '%s[ OK ]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
err(){ printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){
    cat <<'HELP'
Використання:
  ./setup.sh --name hap-ac                 Завантажити config.rsc без застосування
  ./setup.sh --name hap-ac --reset         Завантажити та виконати reset + автозастосування
  ./setup.sh --name hap-ac --dry-run       Показати план без підключення та передачі

Опції:
  --name NAME              Каталог routers/NAME (обов'язково)
  --reset                  Деструктивний reset no-defaults з run-after-reset
  --yes, -y                Не запитувати підтвердження для --reset
  --dry-run                Локальна перевірка та показ команд без мережевих дій
  --key PATH               SSH-ключ (або SSH_KEY у середовищі)
  --insecure-host-key       Не перевіряти SSH host key (лише ізольована лабораторія)
  --help, -h               Довідка

На Arch Linux для парольної автентифікації: sudo pacman -S openssh sshpass
HELP
}

NAME=""; DO_RESET=0; ASSUME_YES=0; DRY_RUN=0
SSH_KEY="${SSH_KEY:-}"; INSECURE_HOST_KEY=0
while (($#)); do
    case "$1" in
        --name) (($# >= 2)) || die "--name потребує значення"; NAME="$2"; shift 2 ;;
        --reset) DO_RESET=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --key) (($# >= 2)) || die "--key потребує шляху"; SSH_KEY="$2"; shift 2 ;;
        --insecure-host-key) INSECURE_HOST_KEY=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Невідома опція: $1" ;;
    esac
done

[[ -n "$NAME" ]] || die "Не вказано --name"
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || die "--name: дозволені малі латинські літери, цифри та дефіс"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/routers/$NAME/config.rsc"
[[ -f "$CONFIG" ]] || die "Не знайдено конфігурацію: $CONFIG"

if ((DRY_RUN == 0)); then
    command -v ssh >/dev/null 2>&1 || die "ssh не знайдено. Arch Linux: sudo pacman -S openssh"
    command -v scp >/dev/null 2>&1 || die "scp не знайдено. Arch Linux: sudo pacman -S openssh"
fi

# Зчитуємо лише прості початкові :global NAME VALUE. Рядки з масивами
# пропускаються, бо setup.sh їх не використовує.
declare -A VARS=()
parse_globals(){
    local line name value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*:global[[:space:]]+([A-Za-z][A-Za-z0-9]*)[[:space:]]+(.+)$ ]] || continue
        name="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
        value="${value%$'\r'}"
        if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then value="${value:1:${#value}-2}"; fi
        VARS["$name"]="$value"
    done < "$1"
}
parse_globals "$CONFIG"
var(){ printf '%s' "${VARS[$1]:-}"; }

HOST="$(var routerHost)"; USER_NAME="$(var routerUser)"; PASSWORD="$(var routerPassword)"
SSH_PORT="$(var routerSshPort)"; FILE_NAME="$(var configFile)"
SSH_PORT="${SSH_PORT:-22}"; FILE_NAME="${FILE_NAME:-config.rsc}"
[[ -n "$HOST" ]] || die "Не задано routerHost у config.rsc"
[[ -n "$USER_NAME" ]] || die "Не задано routerUser у config.rsc"
ADMIN_USER="$(var adminUser)"
[[ -n "$ADMIN_USER" ]] || die "Не задано adminUser у config.rsc"
# routerUser і adminUser можуть відрізнятися: перший використовується лише для
# SSH-підключення setup.sh, другий створюється самою конфігурацією RouterOS.
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && ((10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535)) || die "routerSshPort має бути числом 1..65535"
WINBOX_PORT="$(var routerWinboxPort)"; WINBOX_PORT="${WINBOX_PORT:-8291}"
[[ "$WINBOX_PORT" =~ ^[0-9]+$ ]] && ((10#$WINBOX_PORT >= 1 && 10#$WINBOX_PORT <= 65535)) || die "routerWinboxPort має бути числом 1..65535"
[[ "$WINBOX_PORT" != "$SSH_PORT" ]] || die "routerWinboxPort не може збігатися з routerSshPort"
[[ "$FILE_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "configFile: дозволені лише A-Z, a-z, цифри, крапка, дефіс та підкреслення"
[[ "$FILE_NAME" != "." && "$FILE_NAME" != ".." ]] || die "Некоректне ім'я configFile"

is_true(){ [[ "$(var "$1")" == "true" ]]; }
placeholder(){ [[ "$1" == ЗАМІНІТЬ* || "$1" == CHANGE_ME* || "$1" == REPLACE_ME* ]]; }
PLACEHOLDERS=()
check_secret(){
    local key="$1" description="$2" value
    value="$(var "$key")"
    if [[ -z "$value" ]] || placeholder "$value"; then PLACEHOLDERS+=("$key — $description"); fi
}
check_secret adminPassword "пароль адміністратора"
WIFI_ENABLED=0
if is_true enableWifi2Ghz || is_true enableWifi5Ghz; then WIFI_ENABLED=1; fi
WIFI_DRIVER="$(var wifiDriver)"
if ((WIFI_ENABLED)); then
    case "$WIFI_DRIVER" in
        legacy|wifi-qcom-ac|wifi-qcom) ;;
        *) die "wifiDriver має бути legacy, wifi-qcom-ac або wifi-qcom (коли Wi-Fi увімкнений)" ;;
    esac
    check_secret wifiPassword "пароль основного Wi-Fi"
fi
if is_true enableGuest && is_true enableWifi2Ghz; then check_secret guestPassword "пароль гостьового Wi-Fi"; fi
if is_true enableIot && is_true enableWifi2Ghz; then check_secret iotPassword "пароль IoT Wi-Fi"; fi
WG_MODE="$(var wgEndpointMode)"
WG_MODE="${WG_MODE:-mikrotik-ddns}"
case "$WG_MODE" in
    ip) [[ -n "$(var wgEndpointIp)" ]] || die "Для wgEndpointMode=ip задайте wgEndpointIp"; placeholder "$(var wgEndpointIp)" && die "wgEndpointIp містить плейсхолдер"; check_secret wgPeerKey "публічний ключ WireGuard-клієнта" ;;
    mikrotik-ddns) check_secret wgPeerKey "публічний ключ WireGuard-клієнта" ;;
    disabled) ;;
    *) die "wgEndpointMode має бути ip, mikrotik-ddns або disabled" ;;
esac
if [[ "$WG_MODE" != "disabled" ]]; then
    WG_PORT="$(var wgPort)"
    [[ "$WG_PORT" =~ ^[0-9]+$ ]] && ((10#$WG_PORT >= 1 && 10#$WG_PORT <= 65535)) || die "wgPort має бути числом 1..65535"
fi
if is_true enableBruteforce; then
    BF_PORTS="$(var bfPorts)"
    [[ "$BF_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]] || die "bfPorts: очікується список портів через кому, наприклад \"22,8291\""
fi
if is_true enableWanSsh || is_true enableWanWinbox; then
    [[ -n "$(var wanAdminAddresses)" ]] || die "Для WAN SSH/Winbox задайте wanAdminAddresses"
fi

if ((${#PLACEHOLDERS[@]})); then
    warn "Виявлено незаповнені обов'язкові секрети:"
    printf '  - %s\n' "${PLACEHOLDERS[@]}" >&2
    if ((DRY_RUN)); then
        warn "Dry-run продовжується без мережевих дій; реальне завантаження заблоковано."
    elif ((DO_RESET)); then
        die "--reset заборонено: замініть плейсхолдери перед скиданням роутера"
    else
        die "Передача конфігурації з активними плейсхолдерами заборонена. Виправте config.rsc."
    fi
fi

if ((DO_RESET && DRY_RUN == 0 && ASSUME_YES == 0)); then
    warn "RESET видалить поточну конфігурацію роутера $HOST."
    read -r -p "Продовжити? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Скасовано користувачем"
fi

if ((INSECURE_HOST_KEY)); then
    warn "Перевірку SSH host key вимкнено. Можливий MITM."
    HOSTKEY_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null)
else
    HOSTKEY_OPTS=(-o StrictHostKeyChecking=accept-new)
fi

MUX_DIR=""
cleanup(){
    if [[ -n "$MUX_DIR" && -S "$MUX_DIR/control" ]]; then
        ssh -S "$MUX_DIR/control" -O exit -p "$SSH_PORT" "$USER_NAME@$HOST" >/dev/null 2>&1 || true
    fi
    [[ -z "$MUX_DIR" ]] || rm -rf -- "$MUX_DIR"
}
trap cleanup EXIT

SSH_BASE=("${HOSTKEY_OPTS[@]}" -o LogLevel=ERROR -o ConnectTimeout=10 -p "$SSH_PORT")
if [[ -n "$SSH_KEY" ]]; then
    [[ -f "$SSH_KEY" ]] || die "SSH-ключ не знайдено: $SSH_KEY"
    SSH_BASE+=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o PasswordAuthentication=no)
    AUTH_MODE=key
else
    if ((DRY_RUN == 0)); then
        command -v sshpass >/dev/null 2>&1 || die "Потрібен sshpass. Arch Linux: sudo pacman -S sshpass"
        [[ -n "$PASSWORD" ]] || die "Не задано routerPassword для парольної SSH-автентифікації"
        placeholder "$PASSWORD" && die "routerPassword містить плейсхолдер. Заповніть його або використайте --key"
    fi
    AUTH_MODE=password
fi

ssh_run(){
    local -a opts=("${SSH_BASE[@]}")
    if [[ -n "$MUX_DIR" ]]; then opts+=(-o ControlMaster=auto -o ControlPath="$MUX_DIR/control" -o ControlPersist=10m); fi
    if [[ "$AUTH_MODE" == password ]]; then SSHPASS="$PASSWORD" sshpass -e ssh "${opts[@]}" "$USER_NAME@$HOST" "$@";
    else ssh "${opts[@]}" "$USER_NAME@$HOST" "$@"; fi
}
scp_run(){
    local -a opts=("${HOSTKEY_OPTS[@]}" -o LogLevel=ERROR -o ConnectTimeout=10 -P "$SSH_PORT")
    if [[ -n "$MUX_DIR" ]]; then opts+=(-o ControlMaster=auto -o ControlPath="$MUX_DIR/control" -o ControlPersist=10m); fi
    if [[ "$AUTH_MODE" == password ]]; then SSHPASS="$PASSWORD" sshpass -e scp "${opts[@]}" "$CONFIG" "$USER_NAME@$HOST:/$FILE_NAME";
    else scp "${opts[@]}" "$CONFIG" "$USER_NAME@$HOST:/$FILE_NAME"; fi
}

info "Роутер: $NAME ($HOST:$SSH_PORT)"
info "Конфігурація: $CONFIG"
info "Файл призначення: /$FILE_NAME"
if ((DO_RESET)); then info "Режим: завантаження + reset no-defaults + run-after-reset"; else info "Режим: лише завантаження, без застосування"; fi
if ((WIFI_ENABLED)); then info "Wi-Fi: увімкнений, вибраний драйвер $WIFI_DRIVER"; else info "Wi-Fi: вимкнений, блок Wi-Fi буде пропущено"; fi
info "WireGuard: $WG_MODE"
if [[ "$WG_MODE" == ip ]]; then info "WireGuard endpoint: $(var wgEndpointIp):$(var wgPort)"; elif [[ "$WG_MODE" == mikrotik-ddns ]]; then info "WireGuard endpoint: домен MikroTik Cloud DDNS (див. /ip cloud print), порт $(var wgPort)"; else info "WireGuard вимкнений"; fi

if ((DRY_RUN)); then
    info "[dry-run] SSH-перевірка: $USER_NAME@$HOST:$SSH_PORT"
    info "[dry-run] SCP: $CONFIG -> $USER_NAME@$HOST:/$FILE_NAME"
    if ((DO_RESET)); then info "[dry-run] /system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=$FILE_NAME"; fi
    ok "Локальні перевірки пройдено; мережеві дії не виконувалися"
    exit 0
fi

MUX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mikrotik-ssh.XXXXXX")"
chmod 700 "$MUX_DIR"
if ! ssh_run ':put connected' >/dev/null; then die "SSH-підключення не вдалося: перевірте хост, порт, користувача та автентифікацію"; fi
ok "SSH-підключення встановлено"

if ! scp_run; then
    warn "Передача через SSH multiplexing не вдалася; повторюю без multiplexing"
    ssh -S "$MUX_DIR/control" -O exit -p "$SSH_PORT" "$USER_NAME@$HOST" >/dev/null 2>&1 || true
    MUX_DIR=""
    scp_run || die "SCP-передача не вдалася"
fi
ok "Файл успішно завантажено"

if ((DO_RESET)); then
    info "Надсилаю reset no-defaults; skip-backup=yes не створює резервну копію перед reset"
    printf 'y\n' | ssh_run "/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=$FILE_NAME" || warn "SSH завершився під час перезавантаження — це очікувана поведінка"
    ok "Команду reset надіслано. Після перезапуску RouterOS має виконати $FILE_NAME"
else
    info "Файл лише завантажено. Для ручного застосування виконайте на роутері:"
    info "  /import file-name=$FILE_NAME"
fi
ok "Готово"
