#!/usr/bin/env bash
# Функціональні тести без реального сервера:
#  - `ssh` — заглушка, що виконує віддалену команду ЛОКАЛЬНО через sh -c;
#  - `rsync` — заглушка, що логує аргументи, повертає код з RSYNC_STUB_RC
#    і друкує вміст RSYNC_STUB_OUT.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"
export XDG_RUNTIME_DIR="$TMP/run"
export BACKUP_SYNC_CONFIG="$TMP/test.conf"
export RSYNC_LOG="$TMP/rsync.log"
export RSYNC_SCAN_LOG="$TMP/rsync-scan.log"
export SSH_ARGS_LOG="$TMP/ssh-args.log"
export PATH="$TMP/bin:$PATH"

REMOTE="$TMP/remote"
STATE="$XDG_STATE_HOME/backup-sync"
TS_OLD="2020-01-01_00-00-00"
fail=0
out=""
rc=0

mkdir -p "$TMP/bin" "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$REMOTE"

cat > "$TMP/bin/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SSH_ARGS_LOG:-/dev/null}"
while (($#)); do
    case "$1" in
        -o|-p|-i) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
shift                                   # host
if [[ -n "${SSH_STUB_FAIL_DF:-}" && "$*" == *"df -"* ]]; then exit 255; fi
export RSYNC_STUB_CAPS="${RSYNC_STUB_REMOTE_CAPS:-${RSYNC_STUB_CAPS:-}}"
if [[ "$*" == *"-mtime"* ]]; then
    [[ -n "${SSH_STUB_FAIL_MTIME:-}" ]] && exit 255
    if [[ -n "${SSH_STUB_CHECK_LOCK_ON_CLEANUP:-}" ]]; then
        if [[ -d "$SSH_STUB_CHECK_LOCK_ON_CLEANUP" ]]; then echo "CLEANUP_LOCK=present" >> "$RSYNC_LOG"; else echo "CLEANUP_LOCK=absent" >> "$RSYNC_LOG"; fi
    fi
fi
exec sh -c "$*"
STUB

cat > "$TMP/bin/rsync" <<'STUB'
#!/usr/bin/env bash
# --version: можливості (для перевірки -H/-A/-X). Не логуємо як запуск синхронізації.
if [[ "${1:-}" == "--version" ]]; then
    if [[ -n "${RSYNC_STUB_CAPS:-}" ]]; then
        printf '%s\n' "$RSYNC_STUB_CAPS"
    else
        printf '%s\n' "rsync  version 3.2.7  protocol version 31" "Capabilities:" \
            "    64-bit files, 64-bit inums, symlinks, hardlinks, hardlink-specials," \
            "    IPv6, atimes, batches, inplace, append, ACLs, xattrs, optional protect-args," \
            "    iconv, prealloc, stop-at, no crtimes"
    fi
    exit 0
fi

# dry-run-АНАЛІЗ (scan): --dry-run + --stats і без --verbose. Окремий журнал, окремі змінні керування.
dry=0; stats=0; verbose=0
for a in "$@"; do
    case "$a" in --dry-run) dry=1 ;; --stats) stats=1 ;; --verbose) verbose=1 ;; esac
done
if ((dry && stats && !verbose)); then
    printf '%s\n' "$*" >> "${RSYNC_SCAN_LOG:-/dev/null}"
    if [[ "${RSYNC_SCAN_OUT+x}" ]]; then
        printf '%s\n' "$RSYNC_SCAN_OUT"
    else
        echo "Total transferred file size: 0 bytes"
    fi
    exit "${RSYNC_SCAN_RC:-0}"
fi

printf '%s\n' "$*" >> "$RSYNC_LOG"
for a in "$@"; do
    if [[ "$a" == --backup-dir=* && -n "${RSYNC_STUB_TOUCH:-}" && "$a" == *"/${RSYNC_STUB_TOUCH}" ]]; then
        mkdir -p "${a#--backup-dir=}" && : > "${a#--backup-dir=}/old.txt"
    fi
done
if [[ -n "${RSYNC_STUB_CHECK_LOCK:-}" ]]; then
    if [[ -d "$RSYNC_STUB_CHECK_LOCK" ]]; then echo "LOCK=present" >> "$RSYNC_LOG"; else echo "LOCK=absent" >> "$RSYNC_LOG"; fi
fi
if [[ -n "${RSYNC_STUB_STEAL_LOCK:-}" ]]; then printf 'other-token\nother owner\n' > "$RSYNC_STUB_STEAL_LOCK/owner"; fi
[[ -n "${RSYNC_STUB_OUT:-}" ]] && printf '%s\n' "$RSYNC_STUB_OUT"
[[ -n "${RSYNC_STUB_SLEEP:-}" ]] && sleep "$RSYNC_STUB_SLEEP"
exit "${RSYNC_STUB_RC:-0}"
STUB
chmod +x "$TMP/bin/ssh" "$TMP/bin/rsync"

write_conf() {   # $1 — додаткові рядки конфігу
    cat > "$BACKUP_SYNC_CONFIG" <<CONF
LOCAL_DIR="$HOME"
REMOTE_DIR="$REMOTE"
BACKUP_DIRS=(A B)
EXCLUDE_FILE="$TMP/no-exclude"
STATE_DIR="$STATE"
LOG_DIR="\$STATE_DIR/log"
MIN_FREE_MIB=1
RSYNC_COMPRESS=false
${1:-}
CONF
}

reset_env() {
    rm -rf "$HOME" "$REMOTE" "$STATE" "$RSYNC_LOG" "$RSYNC_SCAN_LOG"
    mkdir -p "$HOME/A" "$HOME/B" "$REMOTE/A" "$REMOTE/B"
    : > "$HOME/A/f.txt"; : > "$HOME/B/f.txt"
    : > "$REMOTE/A/f.txt"; : > "$REMOTE/B/f.txt"
    : > "$RSYNC_LOG"; : > "$RSYNC_SCAN_LOG"
    unset RSYNC_STUB_RC RSYNC_STUB_OUT RSYNC_STUB_TOUCH SSH_STUB_FAIL_DF \
          RSYNC_STUB_CHECK_LOCK RSYNC_STUB_STEAL_LOCK RSYNC_STUB_SLEEP EXPECT_ERR_TRAP \
          SSH_STUB_FAIL_MTIME SSH_STUB_CHECK_LOCK_ON_CLEANUP \
          RSYNC_SCAN_OUT RSYNC_SCAN_RC RSYNC_STUB_CAPS RSYNC_STUB_REMOTE_CAPS
    : > "$SSH_ARGS_LOG"
    write_conf
}

run() {          # run <args…> → out, rc
    rc=0
    out=$("$ROOT_DIR/backup-sync.sh" "$@" 2>&1 </dev/null) || rc=$?
    assert_no_spurious_err_trap "$*"
}

# Заплановані виходи (die, скасування, verify-код 3…) НЕ мають друкувати «Неочікувана помилка».
assert_no_spurious_err_trap() {
    if [[ -z "${EXPECT_ERR_TRAP:-}" ]] && grep -q 'Неочікувана помилка' <<<"$out"; then
        printf '[FAIL] хибне ERR-trap повідомлення у запуску: %s\n' "$1"
        printf '%s\n' "$out" | grep 'Неочікувана помилка' | sed 's/^/       | /'
        fail=1
    fi
}

check() {        # check "опис" <команда…>
    local name="$1"; shift
    if "$@"; then
        printf '[PASS] %s\n' "$name"
    else
        printf '[FAIL] %s\n' "$name"
        printf '       rc=%s\n%s\n' "$rc" "$(printf '%s\n' "$out" | tail -n 15 | sed 's/^/       | /')"
        fail=1
    fi
}

# shellcheck disable=SC2329  # викликається опосередковано: check "опис" has …  (через "$@")
has()    { grep -q -- "$1" <<<"$out"; }

# Найновіший лог-файл (без ls у підстановці: SC2012).
newest_log() {
    local f newest=""
    for f in "$STATE"/log/*.log; do
        [[ -e "$f" ]] || continue
        if [[ -z "$newest" || "$f" -nt "$newest" ]]; then newest="$f"; fi
    done
    printf '%s' "$newest"
}

# shellcheck disable=SC2329  # викликається опосередковано: check "опис" logged …  (через "$@")
logged() { grep -q -e "$1" "$RSYNC_LOG"; }   # -e: шаблон може починатися з "--"

# --------------------------------------------------------------------
printf '== 1. Recovery: окремий backup-dir для кожного каталогу (UP) ==\n'
reset_env
RSYNC_STUB_TOUCH=A run up -y --host h
check "rc=0" test "$rc" -eq 0
check "backup-dir для A містить /A" logged "backup-dir=$REMOTE/.backup-sync-recovery/[0-9-]*_[0-9-]*/A"
check "backup-dir для B містить /B" logged "backup-dir=$REMOTE/.backup-sync-recovery/[0-9-]*_[0-9-]*/B"
check "немає спільного backup-dir без імені каталогу" \
    bash -c "! grep -E -- 'backup-dir=[^ ]*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2} ' '$RSYNC_LOG'"
check "порожній recovery для B прибрано, для A (є файл) залишено" \
    bash -c "d=\$(ls -d '$REMOTE'/.backup-sync-recovery/*/); [[ -f \"\$d/A/old.txt\" && ! -e \"\$d/B\" ]]"

printf '\n== 2. Recovery для DOWN (локально) ==\n'
reset_env
RSYNC_STUB_TOUCH=B run down -y --host h
check "rc=0" test "$rc" -eq 0
check "DOWN має --backup" logged "--backup "
check "backup-dir для A у LOCAL_RECOVERY_DIR" logged "backup-dir=$STATE/recovery-down/[0-9-]*_[0-9-]*/A"
check "backup-dir для B у LOCAL_RECOVERY_DIR" logged "backup-dir=$STATE/recovery-down/[0-9-]*_[0-9-]*/B"
check "DOWN без DELETE_ON_DOWN не має --delete-delay" bash -c "! grep -q -- '--delete-delay' '$RSYNC_LOG'"
reset_env; write_conf 'RECOVERY_ENABLED=false'
run down -y --host h
check "RECOVERY_ENABLED=false → без --backup" bash -c "! grep -q -- '--backup' '$RSYNC_LOG'"
reset_env
run down --dry-run --host h
check "dry-run → без --backup і без каталогів recovery" \
    bash -c "! grep -q -- '--backup' '$RSYNC_LOG' && [[ ! -d '$STATE/recovery-down' ]]"

printf '\n== 3. cleanup --dry-run і захист від небезпечного RECOVERY_ROOT ==\n'
reset_env
mkdir -p "$REMOTE/.backup-sync-recovery/$TS_OLD/A" "$REMOTE/.backup-sync-recovery/keepme" \
         "$STATE/recovery-down/$TS_OLD/A" "$STATE/recovery-down/keepme" "$STATE/log"
: > "$STATE/log/backup-sync_2020-01-01_00-00-00.log"
touch -d '90 days ago' "$REMOTE/.backup-sync-recovery/$TS_OLD" "$REMOTE/.backup-sync-recovery/keepme" \
                       "$STATE/recovery-down/$TS_OLD" "$STATE/recovery-down/keepme" \
                       "$STATE/log/backup-sync_2020-01-01_00-00-00.log"
run cleanup --dry-run --host h
check "cleanup --dry-run: rc=0" test "$rc" -eq 0
check "cleanup --dry-run нічого не видалив" bash -c "
    [[ -d '$REMOTE/.backup-sync-recovery/$TS_OLD' && -d '$STATE/recovery-down/$TS_OLD' && -f '$STATE/log/backup-sync_2020-01-01_00-00-00.log' ]]"
check "dry-run показав кандидатів (remote)" has "$REMOTE/.backup-sync-recovery/$TS_OLD"
run cleanup --host h
check "cleanup: rc=0" test "$rc" -eq 0
check "cleanup видалив старі TS-каталоги (remote+local) і старий лог" bash -c "
    [[ ! -e '$REMOTE/.backup-sync-recovery/$TS_OLD' && ! -e '$STATE/recovery-down/$TS_OLD' && ! -e '$STATE/log/backup-sync_2020-01-01_00-00-00.log' ]]"
check "cleanup НЕ чіпає каталоги без імені-таймстемпу" bash -c "
    [[ -d '$REMOTE/.backup-sync-recovery/keepme' && -d '$STATE/recovery-down/keepme' ]]"

for bad in '' '../x' 'a/b' '.' '..' 'A'; do
    reset_env; write_conf "RECOVERY_ROOT=\"$bad\""
    mkdir -p "$REMOTE/A/sub"; touch -d '90 days ago' "$REMOTE/A/sub"
    run cleanup --host h
    check "RECOVERY_ROOT='$bad' відхилено, дані не чіпали" bash -c "[[ $rc -ne 0 && -d '$REMOTE/A/sub' ]]"
done
reset_env; write_conf 'BACKUP_DIRS=(A ../etc)'
run up -y --host h
check "BACKUP_DIRS із '..' відхилено" test "$rc" -ne 0

printf '\n== 4. Захист від порожнього джерела і масового видалення ==\n'
reset_env; rm -f "$HOME/A/f.txt"
run up -y --host h
check "порожнє локальне джерело A пропущено, rc=1" test "$rc" -eq 1
check "rsync для A не запускався, для B — так" bash -c "! grep -q '$HOME/A/' '$RSYNC_LOG' && grep -q '$HOME/B/' '$RSYNC_LOG'"
run up -y --allow-empty --host h
check "--allow-empty дозволяє A" bash -c "rc=$rc; [[ \$rc -eq 0 ]] && grep -q '$HOME/A/' '$RSYNC_LOG'"
reset_env; rm -f "$REMOTE/A/f.txt"; write_conf 'DELETE_ON_DOWN=true'
run down -y --host h
check "DOWN+DELETE_ON_DOWN: порожнє remote-джерело пропущено" bash -c "[[ $rc -eq 1 ]] && ! grep -q 'h:$REMOTE/A/' '$RSYNC_LOG'"
reset_env
run up -y --host h
check "за замовчуванням --max-delete=500" logged "--max-delete=500"
run up -y --max-delete 0 --host h
check "--max-delete 0 вимикає ліміт" bash -c "! grep -q -- '--max-delete' <(tail -n 2 '$RSYNC_LOG')"
run up -y --max-delete 7 --host h
check "--max-delete 7 з CLI має пріоритет над конфігом" bash -c "tail -n 2 '$RSYNC_LOG' | grep -q -- '--max-delete=7'"
RSYNC_STUB_RC=25 run up -y --host h
check "rc=25 від rsync → помилка (rc=1) з поясненням" bash -c "[[ $rc -eq 1 ]] && grep -q 'MAX_DELETE' <<<\"\$1\"" _ "$out"
reset_env
RSYNC_STUB_RC=24 run up -y --host h
check "rc=24 (зниклі файли) не є помилкою" test "$rc" -eq 0
reset_env
run down -y --host h
check "DOWN без DELETE_ON_DOWN не обмежений --max-delete" bash -c "! grep -q -- '--max-delete' '$RSYNC_LOG'"

printf '\n== 5. Тихі виходи та exit-коди ==\n'
reset_env
run up --host h
check "без TTY і без -y: зрозуміла помилка, а не мовчазний вихід" bash -c "[[ $rc -eq 1 ]] && grep -q -- '--yes' <<<\"\$1\"" _ "$out"
reset_env; SSH_STUB_FAIL_DF=1 run up -y --host h
check "збій df на remote: повідомлення + підказка --no-space-check" bash -c "[[ $rc -eq 1 ]] && grep -q -- '--no-space-check' <<<\"\$1\"" _ "$out"
reset_env; SSH_STUB_FAIL_DF=1 run up -y --no-space-check --host h
check "--no-space-check обходить збій df" test "$rc" -eq 0

reset_env; RSYNC_STUB_OUT='*deleting   x.txt' run verify up --host h
check "verify: відмінності → код 3" test "$rc" -eq 3
reset_env; RSYNC_STUB_OUT='.d..t...... ./' run verify up --host h
check "verify: лише mtime каталогу → код 0" test "$rc" -eq 0
reset_env; RSYNC_STUB_RC=23 run verify up --host h
check "verify: помилка rsync → код 1" test "$rc" -eq 1
reset_env; RSYNC_STUB_OUT='*deleting   x.txt' run verify down --host h
check "verify down без DELETE_ON_DOWN не передає --delete" bash -c "! grep -q -- '--delete' '$RSYNC_LOG'"
reset_env; run verify up --host h
check "verify up має --delete" logged "--delete"
reset_env
run up -y --host h
check "успішний UP → код 0" test "$rc" -eq 0
check "у нормальному запуску ERR-trap не дає хибних спрацювань" bash -c "! grep -q 'Неочікувана помилка' <<<\"\$1\"" _ "$out"
reset_env; write_conf "STATE_DIR=/proc/no/such/dir"
EXPECT_ERR_TRAP=1 run up -y --host h
check "несподіваний збій (mkdir) не мовчазний: є діагностика ERR-trap" bash -c "[[ $rc -ne 0 ]] && grep -q 'Неочікувана помилка' <<<\"\$1\"" _ "$out"
reset_env; RSYNC_STUB_RC=23 run up -y --host h
check "помилка rsync при UP → код 1" test "$rc" -eq 1

printf '\n== Підтвердження і preview (через псевдо-TTY) ==\n'
if command -v script >/dev/null 2>&1; then
    reset_env; RSYNC_SCAN_OUT=$'*deleting   gone.txt\nTotal transferred file size: 1,048,576 bytes'
    export RSYNC_SCAN_OUT
    rc=0
    out=$(printf 'n\n' | script -qec "$ROOT_DIR/backup-sync.sh up --host h" /dev/null 2>&1) || rc=$?
    unset RSYNC_SCAN_OUT
    assert_no_spurious_err_trap "up (pty, скасування)"
    check "скасування → код 4, preview показав видалення" bash -c "[[ $rc -eq 4 ]] && grep -q 'видалити' <<<\"\$1\"" _ "$out"
else
    printf '[SKIP] немає script(1)\n'
fi

printf '\n== 6. verify: напрямок може стояти будь-де ==\n'
reset_env; run verify --host h both
check "verify --host h both → обидва напрямки" bash -c "[[ $rc -eq 0 ]] && [[ \$(grep -c 'archive' '$RSYNC_LOG') -eq 4 ]]"
reset_env; run verify --host h down
check "verify --host h down → лише down (2 виклики)" bash -c "[[ $rc -eq 0 ]] && [[ \$(grep -c 'archive' '$RSYNC_LOG') -eq 2 ]]"
reset_env; run up down --host h
check "позиційний напрямок поза verify відхиляється (код 2)" test "$rc" -eq 2

printf '\n== 7. SSH: IdentitiesOnly, StrictHostKeyChecking, лапки в --rsh ==\n'
reset_env; : > "$TMP/my key"
write_conf "SSH_IP=127.0.0.1
SSH_PORT=22
SSH_USER=u
SSH_KEY=\"$TMP/my key\""
run up -y
check "прямий режим: rc=0" test "$rc" -eq 0
check "ssh отримує -o IdentitiesOnly=yes" bash -c "grep -q 'IdentitiesOnly=yes' '$SSH_ARGS_LOG'"
check "--rsh бере шлях із пробілом в одинарні лапки" logged "--rsh=ssh .* -i '$TMP/my key' -o IdentitiesOnly=yes"
reset_env; run up -y --host h
check "режим --host (alias): без IdentitiesOnly" bash -c "! grep -q 'IdentitiesOnly' '$SSH_ARGS_LOG'"
check "за замовчуванням StrictHostKeyChecking не задається" bash -c "! grep -q 'StrictHostKeyChecking' '$SSH_ARGS_LOG'"
reset_env; write_conf 'SSH_STRICT_HOST_KEY_CHECKING=accept-new'
run up -y --host h
check "SSH_STRICT_HOST_KEY_CHECKING=accept-new передається в ssh" bash -c "grep -q 'StrictHostKeyChecking=accept-new' '$SSH_ARGS_LOG'"
check "...і в --rsh для rsync" logged "StrictHostKeyChecking=accept-new"
reset_env; write_conf 'SSH_STRICT_HOST_KEY_CHECKING=off'
run up -y --host h
check "некоректне значення SSH_STRICT_HOST_KEY_CHECKING відхилено" test "$rc" -ne 0

printf '\n== 8. Remote lock між ПК ==\n'
LOCK="$REMOTE/.backup-sync.lock"
reset_env; RSYNC_STUB_CHECK_LOCK="$LOCK" run up -y --host h
check "UP: під час rsync lock є" logged "LOCK=present"
check "UP: після завершення lock знято" test ! -e "$LOCK"
reset_env; RSYNC_STUB_CHECK_LOCK="$LOCK" run up --dry-run --host h
check "dry-run: lock не береться" logged "LOCK=absent"
reset_env; RSYNC_STUB_CHECK_LOCK="$LOCK" run verify up --host h
check "verify: lock не береться" logged "LOCK=absent"
reset_env; RSYNC_STUB_RC=23 RSYNC_STUB_CHECK_LOCK="$LOCK" run up -y --host h
check "lock знімається і після помилки rsync" test ! -e "$LOCK"

reset_env; mkdir "$LOCK"; printf 'tok\nhost=otherpc user=bob pid=1 cmd=up started=2026-10-18 10:00:00\n' > "$LOCK/owner"
run up -y --host h
check "зайнятий lock: відмова (код 1) із відомостями про власника" bash -c "[[ $rc -eq 1 ]] && grep -q 'otherpc' <<<\"\$1\" && grep -q -- '--break-lock' <<<\"\$1\"" _ "$out"
check "...rsync не запускався" bash -c "[[ ! -s '$RSYNC_LOG' ]]"
check "...чужий lock не зачеплено" test -d "$LOCK"
run cleanup --host h
check "cleanup теж поважає lock" test "$rc" -eq 1
run cleanup --dry-run --host h
check "cleanup --dry-run lock не потребує" test "$rc" -eq 0
run verify up --host h
check "verify працює при чужому lock" test "$rc" -eq 0
run up -y --break-lock --host h
check "--break-lock: запуск проходить" test "$rc" -eq 0
check "...і після нього lock знято" test ! -e "$LOCK"

reset_env; RSYNC_STUB_STEAL_LOCK="$LOCK" run up -y --host h
check "якщо lock перехопив інший запуск — наш не видаляє чужий" test -d "$LOCK"

printf '\n== 9. Сигнали (Ctrl-C / TERM): фінал не губиться, lock знімається ==\n'

# «Ворожий» tee: помирає від INT/TERM (як tee, що не успадкував ігнорування сигналів — так поводиться
# частина версій bash при `trap '' INT; exec tee`). Python, бо лише він може скинути успадковане ігнорування.
HOSTILE="$TMP/hostile"
mkdir -p "$HOSTILE"
cat > "$HOSTILE/tee" <<'PYTEE'
#!/usr/bin/env python3
import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
signal.signal(signal.SIGTERM, signal.SIG_DFL)
args = sys.argv[1:]
if args and args[0] == "-a":
    args = args[1:]
files = [open(a, "ab") for a in args]
out = sys.stdout.buffer
while True:
    data = os.read(0, 65536)
    if not data:
        break
    out.write(data); out.flush()
    for f in files:
        f.write(data); f.flush()
PYTEE
chmod +x "$HOSTILE/tee"

# tee, що ПІСЛЯ сигналу ще кілька секунд лишається живим, але вже закрив вхід (не читає pipe).
# Перевірка «чи живий» (kill -0) каже «так», а запис у pipe безнадійний — саме це гонка, від якої
# захищає безумовне відключення в on_signal.
LINGER="$TMP/linger"; mkdir -p "$LINGER"
cat > "$LINGER/tee" <<'PYTEE'
#!/usr/bin/env python3
import os, signal, sys, time
def linger(signum, frame):
    os.close(0)          # більше не читаємо: pipe без читача
    time.sleep(3)        # ...але процес ще живий
    os._exit(0)
signal.signal(signal.SIGINT, linger)
signal.signal(signal.SIGTERM, linger)
args = sys.argv[1:]
if args and args[0] == "-a":
    args = args[1:]
files = [open(a, "ab") for a in args]
out = sys.stdout.buffer
while True:
    try:
        data = os.read(0, 65536)
    except OSError:
        time.sleep(3); os._exit(0)
    if not data:
        break
    out.write(data); out.flush()
    for f in files:
        f.write(data); f.flush()
PYTEE
chmod +x "$LINGER/tee"

# run_signal_case <INT|TERM> [каталог-із-заглушками-для-PATH] [nosetsid] → sig_rc, out, sig_log
run_signal_case() {
    local sig="$1" extra="${2:-}" nosetsid="${3:+1}"
    reset_env
    sig_rc=$(PATH="${extra:+$extra:}$PATH" BACKUP_SYNC_NO_SETSID="$nosetsid" RSYNC_STUB_SLEEP=20 SIG="$sig" BS_ROOT="$ROOT_DIR" OUTF="$TMP/sig.out" python3 - <<'PY'
import os, signal, subprocess, time
sig = getattr(signal, "SIG" + os.environ["SIG"])
rlog = os.environ["RSYNC_LOG"]
with open(os.environ["OUTF"], "w") as out:
    p = subprocess.Popen([os.environ["BS_ROOT"] + "/backup-sync.sh", "up", "-y", "--host", "h"],
                         stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                         start_new_session=True,
                         preexec_fn=lambda: [signal.signal(s, signal.SIG_DFL) for s in (signal.SIGINT, signal.SIGTERM)])
    for _ in range(100):
        if os.path.exists(rlog) and os.path.getsize(rlog) > 0:
            break
        time.sleep(0.1)
    os.killpg(p.pid, sig)
    print(p.wait(timeout=30))
PY
    ) || sig_rc="python-error"
    out=$(<"$TMP/sig.out")
    sig_log=$(newest_log)
}

if command -v python3 >/dev/null 2>&1; then
    for sig in INT TERM; do
        want=130; [[ "$sig" == TERM ]] && want=143

        run_signal_case "$sig"
        check "$sig: код виходу $want" test "$sig_rc" = "$want"
        check "$sig: повідомлення про сигнал є і в консолі, і в лог-файлі" \
            bash -c "grep -q 'Отримано сигнал $sig' '$TMP/sig.out' && grep -q 'Отримано сигнал $sig' '$sig_log'"
        check "$sig: remote-lock знято" test ! -e "$LOCK"
        check "$sig: режим запису логу — ізольований tee (setsid)" bash -c "grep -q 'tee у власній сесії' '$TMP/sig.out'"

        if command -v setsid >/dev/null 2>&1; then
            run_signal_case "$sig" "$HOSTILE"
            check "$sig + tee, що вмирає від сигналів: ізоляція (setsid) його рятує, код $want" test "$sig_rc" = "$want"
            check "$sig + ворожий tee: повідомлення і в консолі, і в лог-файлі" \
                bash -c "grep -q 'Отримано сигнал $sig' '$TMP/sig.out' && grep -q 'Отримано сигнал $sig' '$sig_log'"
            check "$sig + ворожий tee: remote-lock знято" test ! -e "$LOCK"
        fi

        run_signal_case "$sig" "$HOSTILE" nosetsid
        check "$sig без ізоляції і tee помер: скрипт НЕ гине від SIGPIPE (код $want, не -13)" test "$sig_rc" = "$want"
        check "$sig без ізоляції: повідомлення про сигнал виведено в консоль" \
            bash -c "grep -q 'Отримано сигнал $sig' '$TMP/sig.out'"
        check "$sig без ізоляції: підсумок дописано в лог-файл напряму" \
            bash -c "grep -q 'Отримано сигнал $sig' '$sig_log'"
        check "$sig без ізоляції: remote-lock знято" test ! -e "$LOCK"
        check "$sig без ізоляції: це справді запасний режим (а не ізоляція)" bash -c "grep -q 'запасний режим без setsid' '$TMP/sig.out'"

        run_signal_case "$sig" "$LINGER" nosetsid
        check "$sig без ізоляції, tee ще живий, але не читає (гонка): код $want" test "$sig_rc" = "$want"
        check "$sig ...повідомлення про сигнал не губиться в консолі" bash -c "grep -q 'Отримано сигнал $sig' '$TMP/sig.out'"
        check "$sig ...і є в лог-файлі" bash -c "grep -q 'Отримано сигнал $sig' '$sig_log'"
        check "$sig ...remote-lock знято" test ! -e "$LOCK"
    done
else
    printf '[SKIP] немає python3\n'
fi

printf '\n== 10. Лог-файл без кольорів і проміжного прогресу ==\n'
reset_env
RSYNC_STUB_OUT=$'  1.00M  50%  1MB/s\r  2.00M 100%  1MB/s\r>f+++++++++ file.txt' run up -y --host h
newest=$(newest_log)
check "не-TTY: у консолі немає ANSI-кодів" bash -c "! grep -q \$'\\x1b' <<<\"\$1\"" _ "$out"
check "у логу залишився лише фінальний стан рядка прогресу" bash -c "grep -q '^>f+++++++++ file.txt' '$newest' && ! grep -q '50%' '$newest'"
if command -v script >/dev/null 2>&1; then
    reset_env
    rc=0
    out=$(printf 'n\n' | TERM=xterm script -qec "$ROOT_DIR/backup-sync.sh up --host h" /dev/null 2>&1) || rc=$?
    newest=$(newest_log)
    check "TTY: у консолі кольори є" bash -c "grep -q \$'\\x1b\\\\[' <<<\"\$1\"" _ "$out"
    check "TTY: у лог-файлі кольорів немає" bash -c "! grep -q \$'\\x1b' '$newest'"
    rc=0
    out=$(printf 'n\n' | NO_COLOR=1 TERM=xterm script -qec "$ROOT_DIR/backup-sync.sh up --host h" /dev/null 2>&1) || rc=$?
    check "NO_COLOR вимикає кольори" bash -c "! grep -q \$'\\x1b\\\\[' <<<\"\$1\"" _ "$out"
fi

printf '\n== 11. Права доступу, часові мітки, die, версія bash ==\n'
reset_env
RSYNC_STUB_TOUCH=A run down -y --host h
newest=$(newest_log)
check "новий STATE_DIR має права 700" test "$(stat -c %a "$STATE")" = "700"
check "новий LOG_DIR має права 700" test "$(stat -c %a "$STATE/log")" = "700"
check "файл логу має права 600" test "$(stat -c %a "$newest")" = "600"
check "локальний recovery (DOWN) має права 700" test "$(stat -c %a "$STATE/recovery-down")" = "700"
check "рядки логу мають часову мітку HH:MM:SS" bash -c "grep -Eq '^[0-9]{2}:[0-9]{2}:[0-9]{2} \[INFO\]' '$newest'"
check "...і в консолі" bash -c "grep -Eq '^[0-9]{2}:[0-9]{2}:[0-9]{2} \[ OK \]' <<<\"\$1\"" _ "$out"
reset_env; write_conf 'MAX_DELETE=abc'
run up -y --host h
check "die: фатальна помилка конфігу → код 1, повідомлення з [ERROR] і часом" \
    bash -c "[[ $rc -eq 1 ]] && grep -Eq '^[0-9]{2}:[0-9]{2}:[0-9]{2} \[ERROR\].*MAX_DELETE' <<<\"\$1\"" _ "$out"
check "...і rsync не запускався" bash -c "[[ ! -s '$RSYNC_LOG' ]]"

# Поріг версії bash: копія скрипта з завищеною вимогою має відмовитись із зрозумілим повідомленням.
reset_env
cp -r "$ROOT_DIR" "$TMP/future"
sed -i 's/BASH_VERSINFO\[0\] < 4/BASH_VERSINFO[0] < 99/' "$TMP/future/backup-sync.sh"
rc=0; out=$("$TMP/future/backup-sync.sh" up -y --host h 2>&1 </dev/null) || rc=$?
check "bash старіший за вимогу → код 1 і повідомлення «Потрібен bash»" \
    bash -c "[[ $rc -eq 1 ]] && grep -q 'Потрібен bash' <<<\"\$1\"" _ "$out"

printf '\n== 12. Автоочищення recovery після успішного up/down ==\n'
OLD_R="$REMOTE/.backup-sync-recovery/$TS_OLD"; DECOY_R="$REMOTE/.backup-sync-recovery/keepme"
OLD_L="$STATE/recovery-down/$TS_OLD";           DECOY_L="$STATE/recovery-down/keepme"
seed_recovery() {
    mkdir -p "$OLD_R/A" "$DECOY_R" "$OLD_L/A" "$DECOY_L"
    touch -d '90 days ago' "$OLD_R" "$DECOY_R" "$OLD_L" "$DECOY_L"
}

reset_env; seed_recovery
run up -y --host h
check "за замовчуванням автоочищення ВИМКНЕНО (старі копії лишаються)" test -d "$OLD_R"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
RSYNC_STUB_TOUCH=A run up -y --host h
check "UP+auto: rc=0" test "$rc" -eq 0
check "UP+auto: старий серверний recovery видалено" test ! -e "$OLD_R"
check "UP+auto: каталог без імені-таймстемпу не зачеплено" test -d "$DECOY_R"
check "UP+auto: recovery ПОТОЧНОГО запуску збережено" bash -c "ls '$REMOTE'/.backup-sync-recovery/20[2-9][0-9]-*/A/old.txt >/dev/null 2>&1 && [[ \$(ls -d '$REMOTE'/.backup-sync-recovery/20[2-9][0-9]-* | wc -l) -ge 1 ]]"
check "UP+auto: локальний recovery не чіпали (інший напрямок)" test -d "$OLD_L"
check "UP+auto: у виводі видно, що видалено" bash -c "grep -q 'видалено: .*$TS_OLD' <<<\"\$1\" && grep -q 'видалено 1' <<<\"\$1\"" _ "$out"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
run down -y --host h
check "DOWN+auto: старий локальний recovery видалено" test ! -e "$OLD_L"
check "DOWN+auto: decoy лишився, серверний recovery не чіпали" bash -c "[[ -d '$DECOY_L' && -d '$OLD_R' ]]"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
RSYNC_STUB_RC=23 run up -y --host h
check "при помилках синхронізації автоочищення пропускається" bash -c "[[ $rc -eq 1 && -d '$OLD_R' ]] && grep -q 'пропущено' <<<\"\$1\"" _ "$out"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
run up --dry-run --host h
check "--dry-run автоочищення не виконує" test -d "$OLD_R"
check "--dry-run: секція auto-cleanup не друкується (жодного оманливого «видалено»)" \
    bash -c "! grep -q 'AUTO-CLEANUP' <<<\"\$1\" && ! grep -q 'видалено:' <<<\"\$1\"" _ "$out"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true
RECOVERY_ENABLED=false'; seed_recovery
run up -y --host h
check "RECOVERY_ENABLED=false: автоочищення не виконується" test -d "$OLD_R"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true
KEEP_RECOVERY_DAYS=0'; seed_recovery
RSYNC_STUB_TOUCH=B run up -y --host h
check "KEEP=0: старе видалено, а recovery поточного запуску лишається" \
    bash -c "[[ ! -e '$OLD_R' ]] && ls '$REMOTE'/.backup-sync-recovery/20[2-9][0-9]-*/B/old.txt >/dev/null 2>&1"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
run up -y --no-auto-cleanup --host h
check "--no-auto-cleanup перекриває конфіг" test -d "$OLD_R"
reset_env; seed_recovery
run up -y --auto-cleanup --host h
check "--auto-cleanup вмикає без конфігу" test ! -e "$OLD_R"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
SSH_STUB_FAIL_MTIME=1 run up -y --host h
check "збій очищення НЕ ламає синхронізацію: rc=0 + попередження" \
    bash -c "[[ $rc -eq 0 ]] && grep -q 'Auto-cleanup recovery не вдався' <<<\"\$1\"" _ "$out"
check "...і старі копії лишились" test -d "$OLD_R"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true'; seed_recovery
SSH_STUB_CHECK_LOCK_ON_CLEANUP="$LOCK" run up -y --host h
check "очищення виконується ПІД remote-lock" logged "CLEANUP_LOCK=present"
check "...після завершення lock знято" test ! -e "$LOCK"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=maybe'
run up -y --host h
check "некоректне AUTO_CLEANUP_RECOVERY відхилено" test "$rc" -eq 1

reset_env; seed_recovery
run cleanup --host h
check "ручний cleanup тепер друкує, що видалив" bash -c "grep -q 'видалено\|$TS_OLD' <<<\"\$1\"" _ "$out"

printf '\n== 13. Перемикачі recovery: конфіг і прапорці ==\n'
REC_R="$REMOTE/.backup-sync-recovery"; REC_L="$STATE/recovery-down"
has_rec()  { grep -q -e '--backup-dir=' "$RSYNC_LOG"; }

reset_env; run up -y --host h
check "за замовчуванням UP має recovery" has_rec
reset_env; run down -y --host h
check "за замовчуванням DOWN має recovery" has_rec

reset_env; write_conf 'RECOVERY_UP_ENABLED=false'
run up -y --host h
check "RECOVERY_UP_ENABLED=false: UP без recovery (і без каталогу на сервері)" \
    bash -c "! grep -q -e '--backup' '$RSYNC_LOG' && [[ ! -e '$REC_R' ]]"
check "...з попередженням у виводі" bash -c "grep -q 'Recovery ВИМКНЕНО' <<<\"\$1\"" _ "$out"
: > "$RSYNC_LOG"
run down -y --host h
check "...а DOWN при цьому має recovery" has_rec

reset_env; write_conf 'RECOVERY_DOWN_ENABLED=false'
run down -y --host h
check "RECOVERY_DOWN_ENABLED=false: DOWN без recovery (і без локального каталогу)" \
    bash -c "! grep -q -e '--backup' '$RSYNC_LOG' && [[ ! -e '$REC_L' ]]"
: > "$RSYNC_LOG"
run up -y --host h
check "...а UP при цьому має recovery" has_rec

reset_env; write_conf 'RECOVERY_ENABLED=false'
run up -y --host h; up_has=0; has_rec && up_has=1
: > "$RSYNC_LOG"
run down -y --host h; down_has=0; has_rec && down_has=1
check "RECOVERY_ENABLED=false вимикає recovery в обох напрямках" test "$((up_has + down_has))" -eq 0 -a "$rc" -eq 0

reset_env; run up -y --no-recovery --host h
check "--no-recovery: UP без recovery і без каталогу на сервері" \
    bash -c "! grep -q -e '--backup' '$RSYNC_LOG' && [[ ! -e '$REC_R' ]]"
check "--no-recovery: у виводі явне попередження" bash -c "grep -q 'Recovery ВИМКНЕНО' <<<\"\$1\"" _ "$out"
reset_env; run down -y --no-recovery --host h
check "--no-recovery: DOWN без recovery і без локального каталогу" \
    bash -c "! grep -q -e '--backup' '$RSYNC_LOG' && [[ ! -e '$REC_L' ]]"
reset_env; run up --dry-run --no-recovery --host h
check "--no-recovery + --dry-run: попередження є, rsync без --backup" \
    bash -c "grep -q 'Recovery ВИМКНЕНО' <<<\"\$1\" && ! grep -q -e '--backup' '$RSYNC_LOG'" _ "$out"

reset_env; write_conf 'RECOVERY_ENABLED=false
RECOVERY_UP_ENABLED=false
RECOVERY_DOWN_ENABLED=false'
run up -y --recovery --host h
check "--recovery перекриває конфіг (UP)" has_rec
: > "$RSYNC_LOG"
run down -y --recovery --host h
check "--recovery перекриває конфіг (DOWN)" has_rec

reset_env; run up -y --no-recovery --recovery --host h
check "останній прапорець виграє: --no-recovery --recovery → увімкнено" has_rec
reset_env; run up -y --recovery --no-recovery --host h
check "останній прапорець виграє: --recovery --no-recovery → вимкнено" bash -c "! grep -q -e '--backup' '$RSYNC_LOG'"

for v in RECOVERY_UP_ENABLED RECOVERY_DOWN_ENABLED; do
    reset_env; write_conf "$v=maybe"
    run up -y --host h
    check "некоректне $v відхилено" bash -c "[[ $rc -eq 1 ]] && grep -q '$v' <<<\"\$1\"" _ "$out"
done

reset_env; write_conf 'RECOVERY_ENABLED=false'; mkdir -p "$OLD_R/A" "$OLD_L/A"; touch -d '90 days ago' "$OLD_R" "$OLD_L"
run cleanup --host h
check "ручний cleanup працює і при вимкненому recovery (старі копії не застрягають)" \
    bash -c "[[ $rc -eq 0 && ! -e '$OLD_R' && ! -e '$OLD_L' ]]"

reset_env; write_conf 'AUTO_CLEANUP_RECOVERY=true
RECOVERY_UP_ENABLED=false'; seed_recovery
run up -y --host h
check "автоочищення поважає перемикач напрямку (UP вимкнено → не чистить)" test -d "$OLD_R"
run down -y --host h
check "...а DOWN (увімкнено) чистить локальний" test ! -e "$OLD_L"

if command -v script >/dev/null 2>&1; then
    reset_env
    out=$(printf 'n\n' | script -qec "$ROOT_DIR/backup-sync.sh up --no-recovery --host h" /dev/null 2>&1) || true
    check "підтвердження UP без recovery попереджає про безповоротну втрату" \
        bash -c "grep -q 'втрачаються безповоротно' <<<\"\$1\"" _ "$out"
fi

# ====================================================================
# shellcheck disable=SC2329  # викликається опосередковано: check "опис" in_out …  (через "$@")
in_out()  { grep -q -e "$1" <<<"$out"; }
# shellcheck disable=SC2329  # викликається опосередковано: check "опис" in_scan …  (через "$@")
in_scan() { grep -q -e "$1" "$RSYNC_SCAN_LOG"; }
# shellcheck disable=SC2329  # викликається опосередковано: check "опис" in_sync …  (через "$@")
in_sync() { grep -q -e "$1" "$RSYNC_LOG"; }
# shellcheck disable=SC2329  # викликається опосередковано: check "опис" not …  (через "$@")
not()     { ! "$@"; }
# shellcheck disable=SC2329  # викликається опосередковано: check "опис" line_has …  (через "$@")
line_has() { grep -e "$2" "$1" | grep -q -e "$3"; }   # файл, шаблон рядка, шаблон у цьому рядку
free_mib() { df -Pk "$1" | awk 'NR==2 { print int($4 / 1024) }'; }

printf '\n== 14. Вільне місце: напрямок, обсяг із dry-run, запас ==\n'
F=$(free_mib "$REMOTE")
half=$(( (F / 2 + 10) * 1048576 )); quarter=$(( (F / 4) * 1048576 ))

reset_env; SSH_STUB_FAIL_DF=1 run down -y --host h
check "DOWN перевіряє лише локальний диск: збій remote df не заважає" test "$rc" -eq 0
reset_env; SSH_STUB_FAIL_DF=1 run up -y --host h
check "UP перевіряє саме сервер: збій remote df зупиняє" test "$rc" -eq 1

reset_env; RSYNC_SCAN_OUT="Total transferred file size: $half bytes" run up -y --host h
check "UP: обсяг (сума каталогів) більший за вільне → відмова (код 1)" test "$rc" -eq 1
check "...з поясненням «Недостатньо місця»" in_out "Недостатньо місця на сервері"
check "...синхронізація не запускалась" bash -c "[[ ! -s '$RSYNC_LOG' ]]"
reset_env; RSYNC_SCAN_OUT="Total transferred file size: $half bytes" run down -y --host h
check "DOWN: те саме для локального диска" bash -c "[[ $rc -eq 1 ]] && grep -q 'Недостатньо місця локально' <<<\"\$1\"" _ "$out"
reset_env; RSYNC_SCAN_OUT="Total transferred file size: $quarter bytes" run up -y --host h
check "обсяг менший за вільне → проходить" test "$rc" -eq 0

reset_env; write_conf 'MIN_FREE_MIB=999999999'
run up -y --host h
check "запас MIN_FREE_MIB враховується окремо від обсягу" bash -c "[[ $rc -eq 1 ]] && grep -q 'запас 999999999' <<<\"\$1\"" _ "$out"

reset_env; RSYNC_SCAN_OUT='Total transferred file size: 3,145,728 bytes' run up -y --host h
check "розділювачі розрядів у --stats розбираються (2 × 3 MiB = 6.0 MiB)" in_out "6.0 MiB"
reset_env; RSYNC_SCAN_OUT='' run up -y --host h
check "обсяг невідомий → попередження, а не відмова" bash -c "[[ $rc -eq 0 ]] && grep -q 'не вдалося оцінити' <<<\"\$1\"" _ "$out"
reset_env; RSYNC_SCAN_RC=23 run up -y --host h
check "збій dry-run-аналізу → попередження, синхронізація йде далі" bash -c "[[ $rc -eq 0 ]] && grep -q 'не вдалося оцінити' <<<\"\$1\"" _ "$out"
reset_env; rm -rf "$HOME/A"
run up -y --host h
check "каталог без локального джерела — пропуск, а не «невідомий обсяг»" not in_out 'не вдалося оцінити для: A'

reset_env; write_conf 'SPACE_CHECK_METHOD=threshold'
run up -y --host h
check "threshold: dry-run-аналіз не запускається" bash -c "[[ $rc -eq 0 && ! -s '$RSYNC_SCAN_LOG' ]]"
check "...і метод видно у виводі" in_out 'threshold'
reset_env; run up -y --no-space-check --host h
check "--no-space-check: аналіз не запускається, є попередження" bash -c "[[ ! -s '$RSYNC_SCAN_LOG' ]] && grep -q 'вимкнено' <<<\"\$1\"" _ "$out"
reset_env; run up --dry-run --host h
check "--dry-run: ні аналізу, ні перевірки місця" bash -c "[[ ! -s '$RSYNC_SCAN_LOG' ]] && ! grep -q 'ВІЛЬНЕ МІСЦЕ' <<<\"\$1\"" _ "$out"
reset_env; SSH_STUB_FAIL_DF=1 run verify up --host h
check "verify місце не перевіряє (df не потрібен)" bash -c "[[ $rc -eq 0 && ! -s '$RSYNC_SCAN_LOG' ]]"
reset_env; write_conf 'SPACE_CHECK_METHOD=bogus'
run up -y --host h
check "некоректний SPACE_CHECK_METHOD відхилено" test "$rc" -eq 1

if command -v script >/dev/null 2>&1; then
    reset_env
    out=$(printf 'n\n' | RSYNC_SCAN_OUT=$'>f+++++++++ x.txt\nTotal transferred file size: 3,145,728 bytes' \
        script -qec "$ROOT_DIR/backup-sync.sh up --host h" /dev/null 2>&1) || true
    check "попередній аналіз показує обсяг (≈ 3.0 MiB на каталог)" in_out '3.0 MiB'
    check "один dry-run на каталог: і для місця, і для показу (2 рядки аналізу)" test "$(wc -l < "$RSYNC_SCAN_LOG")" -eq 2
fi

printf '\n== 15. REMOTE_DIR створюється ПІСЛЯ підтвердження ==\n'
reset_env; rm -rf "$REMOTE"
run up -y --host h
check "up -y: REMOTE_DIR створено і запуск успішний" bash -c "[[ $rc -eq 0 && -d '$REMOTE' ]]"
check "...з повідомленням про створення" in_out 'Створено REMOTE_DIR'
check "...перевірка місця працювала для ще не існуючого каталогу (беремо батьківський)" in_out 'Вільно на сервері'
check "...аналіз порівнював з порожнім, а не з неіснуючим remote" not in_scan "h:$REMOTE"

if command -v script >/dev/null 2>&1; then
    reset_env; rm -rf "$REMOTE"
    out=$(printf 'n\n' | script -qec "$ROOT_DIR/backup-sync.sh up --host h" /dev/null 2>&1) || true
    check "скасування: REMOTE_DIR НЕ створено (жодних слідів на сервері)" test ! -e "$REMOTE"
    check "...а користувача попереджено, що його буде створено" in_out 'буде створено на сервері'
fi
reset_env; rm -rf "$REMOTE"
run up --dry-run --host h
check "up --dry-run: REMOTE_DIR не створюється, rc=0" bash -c "[[ $rc -eq 0 && ! -e '$REMOTE' ]]"
check "...dry-run порівнюється з порожнім (rsync не звертається до неіснуючого remote)" \
    bash -c "grep -q 'порівнюється з порожнім' <<<\"\$1\" && ! grep -q 'h:$REMOTE' '$RSYNC_LOG'" _ "$out"
reset_env; rm -rf "$REMOTE"
run down -y --host h
check "down без REMOTE_DIR: помилка" bash -c "[[ $rc -eq 1 ]] && grep -q 'REMOTE_DIR не існує' <<<\"\$1\"" _ "$out"
reset_env; rm -rf "$REMOTE"
run verify up --host h
check "verify без REMOTE_DIR: помилка" test "$rc" -eq 1
reset_env
run up -y --host h
check "якщо REMOTE_DIR існує — повідомлення про створення немає" not in_out 'Створено REMOTE_DIR'
reset_env; rm -rf "$REMOTE/A"
run up -y --host h
check "відсутній лише підкаталог: порожнє призначення тільки для нього" \
    bash -c "! grep -q 'h:$REMOTE/A/' '$RSYNC_SCAN_LOG' && grep -q 'h:$REMOTE/B/' '$RSYNC_SCAN_LOG'"
reset_env; rm -rf "$HOME/A"
run down -y --host h
check "DOWN: відсутній локальний каталог аналізується проти порожнього, rc=0" test "$rc" -eq 0

printf '\n== 16. Поканальні виключення ==\n'
EXD="$TMP/excl.d"; GLOBAL_EX="$TMP/global.conf"
mkdir -p "$EXD"; printf '.cache/\n' > "$GLOBAL_EX"; printf 'target/\nbuild/\n' > "$EXD/A.conf"
cfg_ex="EXCLUDE_FILE=\"$GLOBAL_EX\"
EXCLUDE_DIR=\"$EXD\""

reset_env; write_conf "$cfg_ex"
run up -y --host h
check "глобальний файл застосовується до кожного каталогу" bash -c "grep -c -e '--exclude-from=$GLOBAL_EX' '$RSYNC_LOG' | grep -qx 2"
check "файл A.conf — лише для каталогу A" line_has "$RSYNC_LOG" "$HOME/A/" "A.conf"
check "...і НЕ застосовується до B" not line_has "$RSYNC_LOG" "$HOME/B/" "A.conf"
check "ті самі виключення в dry-run-аналізі (A)" line_has "$RSYNC_SCAN_LOG" "$HOME/A/" "A.conf"
check "...і не потрапляють в аналіз B" not line_has "$RSYNC_SCAN_LOG" "$HOME/B/" "A.conf"
check "у виводі видно, які виключення застосовано" in_out 'Виключення:.*A.conf'
check "підсумок режиму показує джерела виключень" in_out 'Excludes'
reset_env; write_conf "$cfg_ex"
run verify up --host h
check "verify використовує ті самі поканальні виключення" bash -c "grep -e '$HOME/A/' '$RSYNC_LOG' | grep -q 'A.conf' && ! grep -e '$HOME/B/' '$RSYNC_LOG' | grep -q 'A.conf'"

reset_env; mkdir -p "$HOME/A/sub" "$REMOTE/A/sub"; : > "$HOME/A/sub/f"; : > "$REMOTE/A/sub/f"
printf 'nested/\n' > "$EXD/A__sub.conf"
write_conf "BACKUP_DIRS=(A/sub B)
$cfg_ex"
run up -y --host h
check "вкладений каталог A/sub → файл A__sub.conf" line_has "$RSYNC_LOG" "$HOME/A/sub/" "A__sub.conf"
rm -f "$EXD/A__sub.conf"

reset_env; write_conf "EXCLUDE_FILE=\"$GLOBAL_EX\""
run up -y --host h
check "без EXCLUDE_DIR діє лише глобальний файл" bash -c "! grep -q 'A.conf' '$RSYNC_LOG' && grep -q -e '--exclude-from=$GLOBAL_EX' '$RSYNC_LOG'"
reset_env; write_conf "EXCLUDE_DIR=\"$TMP/no-such-dir\""
run up -y --host h
check "неіснуючий EXCLUDE_DIR відхилено" bash -c "[[ $rc -eq 1 ]] && grep -q 'EXCLUDE_DIR' <<<\"\$1\"" _ "$out"

check "постачальний exclude.conf НЕ містить build/ target/ dist/ (не виключає їх скрізь)" \
    bash -c "! grep -Eq '^(build|target|dist)/' '$ROOT_DIR/config/exclude.conf'"
check "...вони перенесені в exclude.d/01_project.conf" \
    bash -c "for p in build target dist; do grep -qx \"\$p/\" '$ROOT_DIR/config/exclude.d/01_project.conf' || exit 1; done"
check "...і в exclude.d/03_work.conf" \
    bash -c "for p in build target dist; do grep -qx \"\$p/\" '$ROOT_DIR/config/exclude.d/03_work.conf' || exit 1; done"
check "постачальний config.conf підключає EXCLUDE_DIR, який існує" \
    bash -c "SCRIPT_DIR='$ROOT_DIR'; STATE_DIR=/x; source '$ROOT_DIR/config/config.conf'; [[ -d \"\$EXCLUDE_DIR\" ]]"

printf '\n== 17. -H / -A / -X (hard-links, acls, xattrs) ==\n'
reset_env; run up -y --host h; run verify up --host h
check "за замовчуванням жодного з --hard-links/--acls/--xattrs" \
    bash -c "! grep -Eq -e '--(hard-links|acls|xattrs)' '$RSYNC_LOG' '$RSYNC_SCAN_LOG'"

for pair in "RSYNC_PRESERVE_HARDLINKS:--hard-links" "RSYNC_PRESERVE_ACLS:--acls" "RSYNC_PRESERVE_XATTRS:--xattrs"; do
    var="${pair%%:*}"; opt="${pair#*:}"
    reset_env; write_conf "$var=true"
    run up -y --host h; up_rc=$rc; : > "$RSYNC_LOG"
    run verify up --host h
    check "$var=true → $opt у синхронізації" bash -c "[[ $up_rc -eq 0 ]]"
    check "...$opt в dry-run-аналізі" in_scan "$opt"
    check "...$opt у verify" in_sync "$opt"
    check "...і інші два прапорці не додаються" \
        bash -c "[[ \$(cat '$RSYNC_LOG' '$RSYNC_SCAN_LOG' | grep -Eo -e '--(hard-links|acls|xattrs)' | sort -u | wc -l) -eq 1 ]]"
done
reset_env; write_conf 'RSYNC_PRESERVE_HARDLINKS=true
RSYNC_PRESERVE_ACLS=true
RSYNC_PRESERVE_XATTRS=true'
run up -y --host h
check "усі три разом: rc=0 і всі три прапорці в rsync" \
    bash -c "[[ $rc -eq 0 ]] && grep -q -e '--hard-links' '$RSYNC_LOG' && grep -q -e '--acls' '$RSYNC_LOG' && grep -q -e '--xattrs' '$RSYNC_LOG'"
check "...підсумок режиму показує, що зберігається" in_out 'Зберігати'

reset_env; write_conf 'RSYNC_PRESERVE_ACLS=true'
RSYNC_STUB_CAPS=$'rsync  version 3.2.7  protocol version 31\nCapabilities:\n    64-bit files, symlinks, hardlinks, no ACLs, xattrs' run up -y --host h
check "локальний rsync без ACL → відмова ДО початку роботи" bash -c "[[ $rc -eq 1 ]] && grep -q 'rsync на local не підтримує ACL' <<<\"\$1\"" _ "$out"
check "...нічого не запускалось" bash -c "[[ ! -s '$RSYNC_LOG' && ! -s '$RSYNC_SCAN_LOG' ]]"
reset_env; write_conf 'RSYNC_PRESERVE_XATTRS=true'
RSYNC_STUB_REMOTE_CAPS=$'rsync  version 3.0.9  protocol version 30\nCapabilities:\n    64-bit files, symlinks, hardlinks, ACLs, no xattrs' run up -y --host h
check "віддалений rsync без xattrs → відмова з вказівкою сторони" \
    bash -c "[[ $rc -eq 1 ]] && grep -q 'rsync на remote не підтримує xattrs' <<<\"\$1\"" _ "$out"
reset_env; write_conf 'RSYNC_PRESERVE_HARDLINKS=true'
RSYNC_STUB_CAPS=$'rsync  version 3.2.7  protocol version 31\nCapabilities:\n    64-bit files, symlinks, no hardlinks' run up -y --host h
check "відсутність hardlinks теж виявляється" test "$rc" -eq 1
reset_env; write_conf 'RSYNC_PRESERVE_ACLS=true'
RSYNC_STUB_CAPS='rsync  version 2.6.9  protocol version 29' run up -y --host h
check "старий формат --version (без Capabilities): попередження, не відмова" \
    bash -c "[[ $rc -eq 0 ]] && grep -q 'Не вдалося визначити підтримку ACL' <<<\"\$1\"" _ "$out"
reset_env
RSYNC_STUB_CAPS=$'Capabilities:\n    no ACLs, no xattrs, no hardlinks' run up -y --host h
check "прапорці вимкнені → можливості rsync не перевіряються" test "$rc" -eq 0
reset_env; write_conf 'RSYNC_PRESERVE_ACLS=true'
RSYNC_STUB_CAPS=$'Capabilities:\n    no ACLs' run cleanup --host h
check "cleanup не перевіряє можливості rsync" test "$rc" -eq 0
reset_env; write_conf 'RSYNC_PRESERVE_ACLS=maybe'
run up -y --host h
check "некоректний RSYNC_PRESERVE_ACLS відхилено" test "$rc" -eq 1

exit "$fail"
