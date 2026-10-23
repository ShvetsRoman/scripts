#!/usr/bin/env bash

# Послідовно прибирає порожні каталоги: <base>/<rel>, <base>/<rel без останнього рівня>, ..., <base>.
# Працює однаково локально і на remote (POSIX sh, аргументи позиційні).
# shellcheck disable=SC2016  # змінні розкриваються в sh -c, не тут
readonly PRUNE_SCRIPT='base=$1; rel=$2
while [ -n "$rel" ]; do
    rmdir "$base/$rel" 2>/dev/null || break
    case "$rel" in
        */*) rel=${rel%/*} ;;
        *) rel= ;;
    esac
done
rmdir "$base" 2>/dev/null
true'

# true, якщо поточний режим може ВИДАЛЯТИ файли на приймачі.
delete_active() {
    [[ "$DIRECTION" == up ]] && return 0
    [[ "$DIRECTION" == down && "$DELETE_ON_DOWN" == true ]]
}

# Чи ввімкнено recovery для поточного напрямку (з урахуванням конфігу і --recovery/--no-recovery).
recovery_enabled() {
    [[ "$RECOVERY_ENABLED" == true ]] || return 1

    case "$DIRECTION" in
        up)   [[ "$RECOVERY_UP_ENABLED" == true ]] ;;
        down) [[ "$RECOVERY_DOWN_ENABLED" == true ]] ;;
        *)    return 0 ;;
    esac
}

# Чи треба ЗАРАЗ зберігати копії (у --dry-run нічого не пишемо).
recovery_active() {
    recovery_enabled && [[ "$DRY_RUN" == false ]]
}

# Корінь recovery поточного запуску (UP — на сервері, DOWN — локально).
recovery_base() {
    if [[ "$DIRECTION" == up ]]; then
        printf '%s/%s/%s' "$REMOTE_DIR" "$RECOVERY_ROOT" "$TIMESTAMP"
    else
        printf '%s/%s' "$LOCAL_RECOVERY_DIR" "$TIMESTAMP"
    fi
}

prepare_recovery_dir() {
    local path="$1"

    if [[ "$DIRECTION" == up ]]; then
        "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p $(shq "$path")"
    else
        ( umask 077; mkdir -p -- "$path" )
    fi
}

prune_recovery_dir() {
    local base="$1" rel="$2"

    if [[ "$DIRECTION" == up ]]; then
        "${SSH_CMD[@]}" "$SSH_TARGET" \
            "sh -c $(shq "$PRUNE_SCRIPT") sh $(shq "$base") $(shq "$rel")" >/dev/null 2>&1 || true
    else
        sh -c "$PRUNE_SCRIPT" sh "$base" "$rel" >/dev/null 2>&1 || true
    fi
}

# --hard-links/--acls/--xattrs за конфігом (спільні для sync, аналізу і verify).
build_preserve_opts() {
    PRESERVE_OPTS=()

    if [[ "$RSYNC_PRESERVE_HARDLINKS" == true ]]; then
        PRESERVE_OPTS+=(--hard-links)
    fi
    if [[ "$RSYNC_PRESERVE_ACLS" == true ]]; then
        PRESERVE_OPTS+=(--acls)
    fi
    if [[ "$RSYNC_PRESERVE_XATTRS" == true ]]; then
        PRESERVE_OPTS+=(--xattrs)
    fi
}

# Виключення для КОНКРЕТНОГО каталогу: глобальний EXCLUDE_FILE + EXCLUDE_DIR/<dir>.conf
# ("/" у імені каталогу замінюється на "__": A/sub -> A__sub.conf). Так build/target/dist
# виключаються лише в проєктних каталогах, а не скрізь (напр., в Documents чи Pictures).
build_exclude_opts() {
    local dir="$1" f

    DIR_EXCLUDE_OPTS=()

    if [[ -f "$EXCLUDE_FILE" ]]; then
        DIR_EXCLUDE_OPTS+=(--exclude-from="$EXCLUDE_FILE")
    fi

    if [[ -n "$EXCLUDE_DIR" ]]; then
        f="${EXCLUDE_DIR}/${dir//\//__}.conf"
        if [[ -f "$f" ]]; then
            DIR_EXCLUDE_OPTS+=(--exclude-from="$f")
        fi
    fi
}

# Опції, спільні для sync і аналізу. БЕЗ --backup-dir (він окремий для кожного каталогу)
# і БЕЗ виключень (вони теж поканальні, див. build_exclude_opts).
build_rsync_opts() {
    build_preserve_opts

    RSYNC_CORE_OPTS=(
        --archive
        --protect-args
        --rsh="$RSH_STRING"
        "${PRESERVE_OPTS[@]}"
    )

    if delete_active; then
        RSYNC_CORE_OPTS+=(--delete-delay)
    fi

    RSYNC_OPTS=(
        "${RSYNC_CORE_OPTS[@]}"
        --verbose
        --human-readable
        --stats
        --itemize-changes
    )

    if [[ "$RSYNC_PARTIAL" == true ]]; then
        RSYNC_OPTS+=(--partial --partial-dir=.rsync-partial)
    fi

    if [[ "$RSYNC_COMPRESS" == true ]]; then
        RSYNC_OPTS+=(--compress)
    fi

    if [[ "$DRY_RUN" == true ]]; then
        RSYNC_OPTS+=(--dry-run)
    else
        RSYNC_OPTS+=(--info=progress2)
    fi

    if delete_active && ((MAX_DELETE > 0)); then
        RSYNC_OPTS+=(--max-delete="$MAX_DELETE")
    fi
}

compute_paths() {
    local dir="$1"

    if [[ "$DIRECTION" == up ]]; then
        P_SRC="${LOCAL_DIR}/${dir}/"
        P_DST="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"
    else
        P_SRC="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"
        P_DST="${LOCAL_DIR}/${dir}/"
    fi
}

mark_failed() {
    FAILED=$((FAILED + 1))
    FAILED_DIRS+=("$1")
}

local_dir_is_empty() {
    [[ -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

# Коди: 0 — каталог є і непорожній; 10 — порожній; 11 — немає; 12 — помилка SSH.
remote_dir_status() {
    local path="$1" q out rc=0
    q=$(shq "$path")

    out=$("${SSH_CMD[@]}" "$SSH_TARGET" \
        "if [ -d $q ]; then find $q -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1; echo __OK__; else echo __MISSING__; fi") || rc=$?

    ((rc == 0)) || return 12
    if [[ "$out" == *__MISSING__* ]]; then
        return 11
    fi
    if [[ "$out" == "__OK__" ]]; then
        return 10
    fi
    return 0
}

print_mode_summary() {
    log_title "РЕЖИМ"

    case "$COMMAND" in
        up)
            log_info "Команда   : UP"
            ;;
        down)
            log_info "Команда   : DOWN"
            ;;
        verify)
            log_info "Команда   : VERIFY ($VERIFY_DIRECTION)"
            ;;
        cleanup)
            log_info "Команда   : CLEANUP"
            ;;
    esac

    if [[ "$COMMAND" == up || "$COMMAND" == down ]]; then
        log_info "Напрямок  : $(direction_label "$DIRECTION")"
        log_info "Dry-run   : $(yes_no "$DRY_RUN")"

        if recovery_enabled; then
            if [[ "$DIRECTION" == up ]]; then
                log_info "Recovery  : $SSH_TARGET:${REMOTE_DIR}/${RECOVERY_ROOT}/<час>/<каталог>/"
            else
                log_info "Recovery  : ${LOCAL_RECOVERY_DIR}/<час>/<каталог>/"
            fi
        else
            log_warn "Recovery ВИМКНЕНО для цього запуску (конфіг або --no-recovery): перезаписані/видалені файли НЕ зберігаються."
        fi

        if delete_active; then
            if ((MAX_DELETE > 0)); then
                log_info "Max delete: ${MAX_DELETE} на каталог"
            else
                log_warn "Max delete: без ліміту"
            fi
        fi
    fi

    if [[ "$COMMAND" != cleanup && "$COMMAND" != help ]]; then
        log_info "SSH       : $SSH_MODE_DESC"
        log_info "Remote    : $SSH_TARGET:$REMOTE_DIR"
        log_info "Local     : $LOCAL_DIR"
        if [[ "$CHECK_DISK_SPACE" == true ]]; then
            log_info "Disk check: ТАК ($SPACE_CHECK_METHOD)"
        else
            log_info "Disk check: НІ"
        fi
        log_info "Excludes  : ${EXCLUDE_FILE}${EXCLUDE_DIR:+ + ${EXCLUDE_DIR}/<каталог>.conf}"

        build_preserve_opts
        if ((${#PRESERVE_OPTS[@]} > 0)); then
            log_info "Зберігати : ${PRESERVE_OPTS[*]}"
        fi
    fi

    log_info "Log       : $LOG_FILE"
    if [[ "$TEE_ISOLATED" == true ]]; then
        log_info "Запис логу: tee у власній сесії (setsid) — переживає Ctrl-C"
    else
        log_warn "Запис логу: запасний режим без setsid — при Ctrl-C лог може бути неповним"
    fi
}

# Порожній тимчасовий каталог: «призначення» для dry-run, коли каталогу призначення ще немає
# (тоді dry-run показує все як нове, а не падає з помилкою).
ensure_scan_empty_dir() {
    [[ -z "$SCAN_EMPTY_DIR" ]] || return 0

    SCAN_EMPTY_DIR=$(mktemp -d)
    TMP_DIRS+=("$SCAN_EMPTY_DIR")
}

# Коди: 0 — каталогу призначення немає, 1 — є, 2 — помилка SSH.
dest_dir_missing() {
    local dir="$1" rc=0

    if [[ "$DIRECTION" == up ]]; then
        if [[ "$REMOTE_DIR_MISSING" == true ]]; then
            return 0
        fi

        remote_dir_status "${REMOTE_DIR}/${dir}" || rc=$?
        case "$rc" in
            11) return 0 ;;
            12) return 2 ;;
            *)  return 1 ;;
        esac
    fi

    [[ ! -d "${LOCAL_DIR}/${dir}" ]]
}

# Єдиний dry-run по всіх каталогах. Його результати (кількість файлів, видалення, обсяг у байтах)
# використовують І перевірка вільного місця, І попередній аналіз перед підтвердженням —
# тож дерево сканується один раз.
scan_changes() {
    local dir out_file err_file rc st scan_dst result upd del bytes ns

    [[ "$SCAN_DONE" == false ]] || return 0
    SCAN_DONE=true

    log_title "АНАЛІЗ ЗМІН (dry-run)"

    for dir in "${BACKUP_DIRS[@]}"; do
        SCAN_UPD["$dir"]=0
        SCAN_DEL["$dir"]=0
        SCAN_BYTES["$dir"]=""
        SCAN_SAMPLE["$dir"]=""
        compute_paths "$dir"

        if [[ "$DIRECTION" == up && ! -d "${LOCAL_DIR}/${dir}" ]]; then
            SCAN_STATE["$dir"]=skipped
            continue
        fi

        scan_dst="$P_DST"
        st=0
        dest_dir_missing "$dir" || st=$?
        case "$st" in
            0)
                ensure_scan_empty_dir
                scan_dst="${SCAN_EMPTY_DIR}/"
                ;;
            2)
                SCAN_STATE["$dir"]=failed
                continue
                ;;
        esac

        build_exclude_opts "$dir"
        out_file=$(mktemp)
        err_file=$(mktemp)
        TMP_FILES+=("$out_file" "$err_file")

        rc=0
        rsync "${RSYNC_CORE_OPTS[@]}" "${DIR_EXCLUDE_OPTS[@]}" \
            --dry-run --itemize-changes --stats "$P_SRC" "$scan_dst" >"$out_file" 2>"$err_file" || rc=$?

        if ((rc != 0 && rc != 24)); then
            SCAN_STATE["$dir"]=failed
            rm -f -- "$out_file" "$err_file"
            continue
        fi

        # Один прохід awk (вивід може бути величезним): лічильники, обсяг і до 10 прикладів видалень.
        result=$(awk '
            /^\*deleting/ { del++; if (n < 10) sample[n++] = $0 }
            /^[<>c][fdLDS]/ { upd++ }
            /^Total transferred file size:/ { b = $0; gsub(/[^0-9]/, "", b); bytes = b; have = 1 }
            END {
                printf "%d %d %s %d\n", upd, del, (have && bytes != "" ? bytes : "-"), n
                for (i = 0; i < n; i++) print sample[i]
            }' "$out_file")
        rm -f -- "$out_file" "$err_file"

        read -r upd del bytes ns <<<"${result%%$'\n'*}"
        SCAN_UPD["$dir"]="$upd"
        SCAN_DEL["$dir"]="$del"
        if ((ns > 0)); then
            SCAN_SAMPLE["$dir"]="${result#*$'\n'}"
        fi

        if [[ "$bytes" == "-" ]]; then
            SCAN_STATE["$dir"]=nobytes
        else
            SCAN_STATE["$dir"]=ok
            SCAN_BYTES["$dir"]="$bytes"
        fi
    done
}

# Показує вже зібраний scan_changes (rsync тут не запускається).
preview_changes() {
    local dir state upd del bytes sample size_text
    local total_upd=0 total_del=0 total_bytes=0 over=false

    log_title "ПОПЕРЕДНІЙ АНАЛІЗ"

    for dir in "${BACKUP_DIRS[@]}"; do
        state="${SCAN_STATE[$dir]}"

        case "$state" in
            skipped)
                log_warn "$dir: немає локально — буде пропущено."
                continue
                ;;
            failed)
                log_warn "$dir: не вдалося оцінити зміни."
                continue
                ;;
        esac

        upd="${SCAN_UPD[$dir]}"
        del="${SCAN_DEL[$dir]}"
        total_upd=$((total_upd + upd))
        total_del=$((total_del + del))

        size_text=""
        if [[ "$state" == ok ]]; then
            bytes="${SCAN_BYTES[$dir]}"
            total_bytes=$((total_bytes + bytes))
            size_text=" (≈ $(human_bytes "$bytes"))"
        fi

        log_info "$dir: оновити/створити ${upd}${size_text}, видалити ${del}"

        if ((del > 0)); then
            sample="${SCAN_SAMPLE[$dir]}"
            printf '%s\n' "$sample" | sed 's/^/        /'
            if ((del > 10)); then
                printf '        … і ще %d\n' $((del - 10))
            fi
            if delete_active && ((MAX_DELETE > 0 && del > MAX_DELETE)); then
                over=true
                log_warn "$dir: ${del} видалень > MAX_DELETE=${MAX_DELETE} — rsync пропустить видалення і завершиться з помилкою."
            fi
        fi
    done

    log_info "Разом: оновити/створити ${total_upd} (≈ $(human_bytes "$total_bytes")), видалити ${total_del}"
    if [[ "$over" == true ]]; then
        log_warn "Щоб дозволити таку кількість видалень: --max-delete N (0 = без ліміту)."
    fi
}

# Підтвердження неможливе без TTY: краще відмовити ДО довгого аналізу.
require_confirmation_possible() {
    [[ "$DRY_RUN" == false ]] || return 0
    [[ "$ASSUME_YES" == false ]] || return 0

    if [[ ! -t 0 ]]; then
        die "Немає інтерактивного терміналу для підтвердження. Використайте -y/--yes або --dry-run."
    fi
}

# Чи потрібен dry-run-аналіз: для оцінки місця і/або для попереднього показу перед запитом.
scan_needed() {
    [[ "$DRY_RUN" == false ]] || return 1

    if [[ "$CHECK_DISK_SPACE" == true && "$SPACE_CHECK_METHOD" == dry-run ]]; then
        return 0
    fi
    [[ "$ASSUME_YES" == false && "$PREVIEW_BEFORE_CONFIRM" == true ]]
}

confirm_sync() {
    [[ "$DRY_RUN" == false ]] || return 0
    [[ "$ASSUME_YES" == false ]] || return 0

    require_confirmation_possible

    log_title "ПІДТВЕРДЖЕННЯ"

    if [[ "$DIRECTION" == up ]]; then
        log_warn "PC -> SERVER працює як mirror."
        log_warn "Файли, яких немає локально, будуть видалені на сервері через --delete-delay."

        if recovery_enabled; then
            log_warn "Старі/видалені серверні версії будуть збережені в recovery."
        else
            log_warn "Recovery ВИМКНЕНО: перезаписані та видалені на сервері файли втрачаються безповоротно."
        fi
    else
        log_warn "SERVER -> PC оновить локальні файли."
        if [[ "$DELETE_ON_DOWN" == true ]]; then
            log_warn "DELETE_ON_DOWN=true: локальні зайві файли також будуть видалені."
        else
            log_warn "DELETE_ON_DOWN=false: локальні зайві файли не видаляються."
        fi

        if recovery_enabled; then
            log_warn "Перезаписані/видалені локальні версії будуть збережені в $LOCAL_RECOVERY_DIR."
        else
            log_warn "Recovery вимкнено: перезаписані локальні файли втрачаються безповоротно."
        fi
    fi

    if [[ "$REMOTE_DIR_MISSING" == true ]]; then
        log_warn "REMOTE_DIR ($REMOTE_DIR) буде створено на сервері."
    fi

    if [[ "$PREVIEW_BEFORE_CONFIRM" == true && "$SCAN_DONE" == true ]]; then
        preview_changes
    fi

    local answer=""
    read -r -p "Продовжити? [y/N] " answer || answer=""

    case "$answer" in
        y|Y|yes|YES)
            ;;
        *)
            log_info "Скасовано."
            exit "$EX_CANCEL"
            ;;
    esac
}

run_sync_all() {
    local dir
    for dir in "${BACKUP_DIRS[@]}"; do
        TOTAL=$((TOTAL + 1))
        sync_one_dir "$dir"
    done
}

sync_one_dir() {
    local dir="$1"
    local rc=0 st=0 base="" backup_dir=""
    local dir_opts=()

    log_title "SYNC: $dir"
    compute_paths "$dir"

    if [[ "$DIRECTION" == up ]]; then
        if [[ ! -d "${LOCAL_DIR}/${dir}" ]]; then
            log_warn "Немає локально: ${LOCAL_DIR}/${dir}"
            mark_failed "$dir"
            return 0
        fi

        if delete_active && [[ "$ALLOW_EMPTY_SOURCE" != true ]] && local_dir_is_empty "${LOCAL_DIR}/${dir}"; then
            log_warn "Локальне джерело порожнє: ${LOCAL_DIR}/${dir}. Mirror видалив би все на сервері — каталог пропущено (дозволити: --allow-empty)."
            mark_failed "$dir"
            return 0
        fi

        if [[ "$DRY_RUN" == false ]]; then
            "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p $(shq "${REMOTE_DIR}/${dir}")" || {
                log_warn "Не вдалося створити remote каталог: ${REMOTE_DIR}/${dir}"
                mark_failed "$dir"
                return 0
            }
        fi
    else
        remote_dir_status "${REMOTE_DIR}/${dir}" || rc=$?
        case "$rc" in
            0)
                ;;
            10)
                if delete_active && [[ "$ALLOW_EMPTY_SOURCE" != true ]]; then
                    log_warn "Remote-джерело порожнє: ${REMOTE_DIR}/${dir}. DELETE_ON_DOWN стер би локальні файли — каталог пропущено (дозволити: --allow-empty)."
                    mark_failed "$dir"
                    return 0
                fi
                ;;
            11)
                log_warn "Немає на remote: ${REMOTE_DIR}/${dir}"
                mark_failed "$dir"
                return 0
                ;;
            *)
                die "SSH-помилка при перевірці ${REMOTE_DIR}/${dir}."
                ;;
        esac
        rc=0

        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p -- "$P_DST" || {
                log_warn "Не вдалося створити локальний каталог: $P_DST"
                mark_failed "$dir"
                return 0
            }
        fi
    fi

    build_exclude_opts "$dir"
    if ((${#DIR_EXCLUDE_OPTS[@]} > 0)); then
        log_info "Виключення: ${DIR_EXCLUDE_OPTS[*]//--exclude-from=/}"
    fi

    # dry-run для каталогу, якого ще немає на стороні призначення: порівнюємо з порожнім,
    # щоб побачити весь обсяг як «нове», а не отримати помилку rsync.
    if [[ "$DRY_RUN" == true ]]; then
        dest_dir_missing "$dir" || st=$?
        if ((st == 0)); then
            ensure_scan_empty_dir
            P_DST="${SCAN_EMPTY_DIR}/"
            log_info "Каталог призначення ще не існує — dry-run порівнюється з порожнім."
        fi
        st=0
    fi

    # Recovery — ОКРЕМИЙ каталог для кожного dir: інакше однакові відносні шляхи
    # з різних BACKUP_DIRS (напр. Documents/notes.txt і 03_work/notes.txt) затирали б одне одного.
    if recovery_active; then
        base=$(recovery_base)
        backup_dir="${base}/${dir}"

        prepare_recovery_dir "$backup_dir" || {
            log_warn "Не вдалося підготувати recovery-каталог: $backup_dir. Каталог пропущено, щоб не перезаписувати дані без резервної копії."
            mark_failed "$dir"
            return 0
        }
        dir_opts=(--backup "--backup-dir=${backup_dir}")
    fi

    rsync "${RSYNC_OPTS[@]}" "${DIR_EXCLUDE_OPTS[@]}" \
        "${dir_opts[@]}" "$P_SRC" "$P_DST" || rc=$?

    if [[ -n "$backup_dir" ]]; then
        prune_recovery_dir "$base" "$dir"
    fi

    case "$rc" in
        0)
            log_ok "$dir синхронізовано"
            SUCCESS=$((SUCCESS + 1))
            ;;
        24)
            log_warn "$dir: частина файлів зникла під час передачі (rc=24) — не вважається помилкою."
            SUCCESS=$((SUCCESS + 1))
            ;;
        25)
            log_warn "$dir: перевищено ліміт видалень (MAX_DELETE=${MAX_DELETE}, rc=25) — видалення пропущено. Перегляньте --dry-run; за потреби: --max-delete N."
            mark_failed "$dir"
            ;;
        *)
            log_warn "$dir — помилка rsync (rc=$rc)"
            mark_failed "$dir"
            ;;
    esac
}

print_final_summary() {
    END_EPOCH=$(date +%s)
    FINAL_RC=$EX_OK

    log_title "ПІДСУМОК"

    if [[ "$COMMAND" == verify ]]; then
        log_info "Усього  : $TOTAL"
        log_info "OK      : $SUCCESS"
        log_info "CHANGED : $CHANGED"
        log_info "FAIL    : $FAILED"

        if ((${#CHANGED_DIRS[@]} > 0)); then
            printf '\n'
            log_warn "Відмінності: ${CHANGED_DIRS[*]}"
        fi

        if ((${#FAILED_DIRS[@]} > 0)); then
            log_warn "З помилками: ${FAILED_DIRS[*]}"
        fi

        if ((START_EPOCH > 0)); then
            log_info "Тривалість : $(human_duration $((END_EPOCH - START_EPOCH)))"
        fi

        if [[ -n "$LOG_FILE" ]]; then
            log_info "Log        : $LOG_FILE"
        fi

        if ((FAILED > 0)); then
            log_warn "VERIFY завершено з помилками."
            FINAL_RC=$EX_FAIL
        elif ((CHANGED > 0)); then
            log_warn "VERIFY завершено: знайдено відмінності (код виходу $EX_DIFF)."
            FINAL_RC=$EX_DIFF
        else
            log_ok "VERIFY завершено: повна відповідність."
        fi
        return 0
    fi

    if [[ "$COMMAND" == up || "$COMMAND" == down ]]; then
        log_info "Усього     : $TOTAL"
        log_info "OK         : $SUCCESS"
        log_info "FAIL       : $FAILED"
    fi

    if ((${#FAILED_DIRS[@]} > 0)); then
        log_warn "З помилками : ${FAILED_DIRS[*]}"
    fi

    if ((START_EPOCH > 0)); then
        log_info "Тривалість : $(human_duration $((END_EPOCH - START_EPOCH)))"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        log_info "Log        : $LOG_FILE"
    fi

    if ((FAILED == 0)); then
        log_ok "Готово."
    else
        log_warn "Готово з помилками."
        FINAL_RC=$EX_FAIL
    fi
    return 0
}
