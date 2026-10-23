#!/usr/bin/env bash

# Коди виходу.
readonly EX_OK=0        # усе гаразд
readonly EX_FAIL=1      # помилка виконання або є каталоги з помилками
readonly EX_USAGE=2     # некоректні аргументи
readonly EX_DIFF=3      # verify: знайдено відмінності (помилок немає)
readonly EX_CANCEL=4    # користувач скасував операцію
FINAL_RC=0

# Шаблон імені recovery-каталогу (TIMESTAMP). Cleanup видаляє ТІЛЬКИ такі каталоги.
readonly TS_NAME_GLOB='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'

COMMAND=""
DIRECTION=""
DRY_RUN=false
ASSUME_YES=false
CHECK_DISK_SPACE=true
SSH_HOST=""
VERIFY_DIRECTION="both"

# Віддалений lock (між різними ПК, що пишуть на один сервер).
readonly REMOTE_LOCK_NAME='.backup-sync.lock'
REMOTE_LOCK_HELD=false
REMOTE_LOCK_TOKEN=""
BREAK_LOCK=false
TEE_PID=""
TEE_ISOLATED=false           # tee запущено у власній сесії (setsid) і не отримує сигналів скрипта
TEE_DETACHED=false           # stdout/stderr уже повернуто з pipe на оригінальні (консоль)

# CLI-перевизначення: конфіг читається ПІСЛЯ parse_args, тому зберігаємо окремо.
CLI_MAX_DELETE=""
CLI_ALLOW_EMPTY=false
CLI_AUTO_CLEANUP=""              # "", true або false
CLI_RECOVERY=""                  # "", true (--recovery) або false (--no-recovery)

TOTAL=0
SUCCESS=0
FAILED=0
CHANGED=0
FAILED_DIRS=()
CHANGED_DIRS=()
TMP_FILES=()
TMP_DIRS=()

# Результати єдиного dry-run-аналізу (scan_changes): по каталогу BACKUP_DIRS.
#   SCAN_STATE: ok | nobytes (rsync не повернув обсяг) | failed | skipped (немає джерела)
declare -A SCAN_STATE=() SCAN_UPD=() SCAN_DEL=() SCAN_BYTES=() SCAN_SAMPLE=()
SCAN_DONE=false
SCAN_EMPTY_DIR=""            # порожній тимчасовий каталог: «призначення» для каталогів, яких ще немає
REMOTE_DIR_MISSING=false     # REMOTE_DIR ще не існує (для up створюється ПІСЛЯ підтвердження)
DIR_EXCLUDE_OPTS=()          # --exclude-from для поточного каталогу (глобальний + exclude.d/<dir>.conf)
PRESERVE_OPTS=()             # --hard-links/--acls/--xattrs за конфігом

START_EPOCH=0
END_EPOCH=0
TIMESTAMP=""
LOG_FILE=""
LOCK_FILE=""
SSH_TARGET=""
SSH_MODE_DESC=""
RSH_STRING=""
P_SRC=""
P_DST=""

SSH_CMD=()
RSYNC_RSH_CMD=()
RSYNC_CORE_OPTS=()
RSYNC_OPTS=()

# ------------------------------------------------------------
# Значення за замовчуванням (config.conf їх перевизначає).
# Потрібні, щоб мінімальний конфіг не падав на `unbound variable`.
# ------------------------------------------------------------
BACKUP_DIRS=()
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/backup-sync"
LOG_DIR="$STATE_DIR/log"
KEEP_LOG_DAYS=10

RECOVERY_ENABLED=true            # загальний вимикач recovery
RECOVERY_UP_ENABLED=true         # recovery для UP   (PC -> SERVER), діє лише при RECOVERY_ENABLED=true
RECOVERY_DOWN_ENABLED=true       # recovery для DOWN (SERVER -> PC), діє лише при RECOVERY_ENABLED=true
RECOVERY_ROOT=".backup-sync-recovery"
KEEP_RECOVERY_DAYS=30
LOCAL_RECOVERY_DIR=""            # порожнє => $STATE_DIR/recovery-down
KEEP_LOCAL_RECOVERY_DAYS=30
AUTO_CLEANUP_RECOVERY=false      # true: після УСПІШНОГО up/down видаляти старі recovery-копії

RSYNC_PARTIAL=true
RSYNC_COMPRESS=false
RSYNC_CHECKSUM_VERIFY=true

SSH_CONNECT_TIMEOUT=10
SSH_SERVER_ALIVE_INTERVAL=15
SSH_SERVER_ALIVE_COUNT_MAX=3
SSH_STRICT_HOST_KEY_CHECKING=""  # порожнє = поведінка ssh за замовчуванням; або yes|no|ask|accept-new

MIN_FREE_MIB=1024                # запас, який має ЛИШИТИСЬ вільним на стороні призначення після передачі
SPACE_CHECK_METHOD="dry-run"     # dry-run: обсяг із dry-run + запас; threshold: лише запас
EXCLUDE_DIR=""                   # каталог поканальних виключень: <EXCLUDE_DIR>/<dir>.conf ("/" -> "__")
RSYNC_PRESERVE_HARDLINKS=false   # -H
RSYNC_PRESERVE_ACLS=false        # -A
RSYNC_PRESERVE_XATTRS=false      # -X
DELETE_ON_DOWN=false

MAX_DELETE=500                   # макс. видалень на ОДИН каталог; 0 = без ліміту
ALLOW_EMPTY_SOURCE=false
PREVIEW_BEFORE_CONFIRM=true

# Кольори лише в інтерактивному терміналі (не в cron/pipe), вимикаються через NO_COLOR.
# Рішення приймається ТУТ, поки stdout ще не перенаправлено у tee.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'; C_RESET=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_RESET=''
fi
readonly C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_RESET
