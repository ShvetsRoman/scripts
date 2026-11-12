#!/usr/bin/env bash
# =============================================================================
# sync_multi.sh — синхронізація ПК <-> СЕРВЕР через rsync (по SSH)
#
# Працює з усіма парами папок зі списку PAIRS.
# Налаштування DELETE / UPDATE / DRY_RUN задаються окремо для push і pull.
# Запуск без аргументів показує довідку.
# =============================================================================

set -uo pipefail

# ============================== НАЛАШТУВАННЯ =================================

# --- Підключення до сервера ---
SERVER_USER="fedora"    # користувач на сервері
SERVER_HOST="127.0.0.1" # IP або доменне імʼя сервера
SERVER_PORT="2222"      # SSH-порт
# SSH_KEY необовʼязковий при запуску з host-аліасом: тоді ключ береться
# з IdentityFile у ~/.ssh/config або з ssh-agent.
# Для fallback-режиму SERVER_* (без host) ключ потрібен ЯВНО — підключення
# йде як user@IP, і запис "Host <аліас>" у ~/.ssh/config не застосовується.
# УВАГА: у cron ключ ОБОВʼЯЗКОВИЙ (або тут, або IdentityFile у ~/.ssh/config),
# бо BatchMode не запитує пароль інтерактивно — запитати його просто ніде.
SSH_KEY=""

# --- Пари папок/файлів: "локальний_шлях|абсолютний_шлях_на_сервері" ---
# Скрипт обробляє ВСІ пари зі списку, по черзі.
# Якщо локальна сторона пари — ОДИНОЧНИЙ ФАЙЛ, синхронізується сам файл:
#   push -> файл кладеться у віддалений каталог, pull -> файл забирається назад.
PAIRS=(
    "$HOME/Documents|~/test"
    "$HOME/00_setup/scripts_bash/zzz_sh/logger.sh|~/bin"
)

# --- Параметри для push (ПК -> СЕРВЕР) ---
PUSH_DELETE=false # true = видаляти на СЕРВЕРІ файли, яких немає на ПК
PUSH_UPDATE=true  # true = rsync --update: пропускати файли, які на СЕРВЕРІ новіші
#        за ті, що на ПК (щоб не затерти свіжіші зміни).
#        Файли, яких на СЕРВЕРІ ще немає, копіюються як завжди.
PUSH_DRY_RUN=false # true = пробний запуск, без реальних змін

# --- Параметри для pull (СЕРВЕР -> ПК) ---
PULL_DELETE=false # true = видаляти на ПК файли, яких немає на СЕРВЕРІ
PULL_UPDATE=true  # true = rsync --update: пропускати файли, які на ПК новіші
#        за ті, що на СЕРВЕРІ. Нові файли копіюються як завжди.
PULL_DRY_RUN=false # true = пробний запуск, без реальних змін

# --- Вивід ---
VERBOSE=true # true = повна інформація (заголовки пар, деталі rsync);
# false = тільки підсумок — один рядок на пару, деталі rsync
# показуються лише якщо пара завершилась з помилкою

# --- Що не синхронізувати (шаблони rsync) ---
EXCLUDES=(".git" "node_modules" "*.tmp" ".DS_Store" "Thumbs.db")

# =============================================================================

# ------------------------------- ДОВІДКА -------------------------------------
show_help() {
    cat <<EOF
Синхронізація ПК <-> СЕРВЕР через rsync.

Використання:
  $(basename "$0") push [host] [опції]    ПК -> СЕРВЕР (усі пари з PAIRS)
  $(basename "$0") pull [host] [опції]    СЕРВЕР -> ПК (усі пари з PAIRS)
  $(basename "$0") help                   Показати цю довідку

host (необов'язково) — Host з ~/.ssh/config (наприклад, fedora).
  User, Port та IdentityFile беруться з ~/.ssh/config,
  SERVER_USER / SERVER_HOST / SERVER_PORT при цьому ігноруються.
  Якщо host не вказано — використовуються налаштування SERVER_* з файлу.

Опції командного рядка (мають ПРІОРИТЕТ над налаштуваннями у файлі):
  -n, --dry-run      Пробний запуск без змін
      --no-dry-run   Виконати реально, навіть якщо *_DRY_RUN=true
      --delete       Видаляти в призначенні файли, яких немає в джерелі
      --no-delete    НЕ видаляти, навіть якщо *_DELETE=true
      --update       Не перезаписувати файли, які в призначенні новіші
      --no-update    Перезаписувати завжди, навіть якщо в призначенні новіше
      --verbose      Повна інформація (перекриває VERBOSE=false)
      --no-verbose   Тільки підсумок (перекриває VERBOSE=true)
  -h, --help         Показати довідку

Що таке --update (rsync -u):
  Якщо файл існує і в призначенні, і в джерелі, але в призначенні він
  НОВІШИЙ (за часом зміни) — rsync його пропускає. Це захищає від втрати
  свіжіших змін. Відсутні в призначенні файли копіюються як завжди.

Конфліктні опції: остання з суперечливих опцій (наприклад, --delete
і --no-delete разом) застосовується з попередженням.

SSH: вхід по ключу (SSH_KEY, ssh-agent або ~/.ssh/config) або по паролю
в інтерактивному терміналі. Без терміналу (cron) — тільки ключ:
підключення в режимі BatchMode, запуск не зависне на запиті пароля.
Пароль/ключ вводиться один раз — ssh-зʼєднання мультиплексується,
усі наступні виклики перевикористовують канал.

Поточні налаштування:
  Сервер:   ${HOST:+$HOST (з ~/.ssh/config)}${HOST:-${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}}
  Пар папок: ${#PAIRS[@]}
  push:  DELETE=${PUSH_DELETE}  UPDATE=${PUSH_UPDATE}  DRY_RUN=${PUSH_DRY_RUN}
  pull:  DELETE=${PULL_DELETE}  UPDATE=${PULL_UPDATE}  DRY_RUN=${PULL_DRY_RUN}

Пари папок (ПК | СЕРВЕР):
EOF
    local p
    for p in "${PAIRS[@]}"; do
        printf '  %s  <->  %s\n' "${p%%|*}" "${p#*|}"
    done
    echo
    echo "Усі параметри змінюються на початку скрипта."
}

# ------------------------------- АРГУМЕНТИ -----------------------------------
# Без аргументів — довідка
if (($# == 0)); then
    show_help
    exit 0
fi

MODE=""
# Host-аліас з ~/.ssh/config (необов'язковий аргумент після push/pull)
HOST=""
# Значення з командного рядка: порожньо = не задано (діє налаштування з файлу),
# true/false = примусово, має пріоритет над налаштуваннями у файлі
CLI_DELETE=""
CLI_UPDATE=""
CLI_DRY_RUN=""
CLI_VERBOSE=""

# Задати CLI-опцію з попередженням про повтор або конфлікт
# (поведінка "остання опція виграє" зберігається, але вже не мовчки)
set_cli() {
    local -n var=$1
    local val="$2" label="$3"
    if [[ -n "$var" ]]; then
        if [[ "$var" == "$val" ]]; then
            echo "Попередження: '$label' вказано повторно."
        else
            echo "Попередження: конфлікт опцій для '$label' (було $var, стає $val); застосовується остання."
        fi
    fi
    var="$val"
}

for arg in "$@"; do
    case "$arg" in
        push | pull)
            if [[ -n "$MODE" && "$MODE" != "$arg" ]]; then
                echo "Попередження: вказано обидва напрямки ($MODE і $arg); буде використано $arg."
            elif [[ -n "$MODE" ]]; then
                echo "Попередження: напрямок '$arg' вказано повторно."
            fi
            MODE="$arg"
            ;;
        -n | --dry-run) set_cli CLI_DRY_RUN true "$arg" ;;
        --no-dry-run) set_cli CLI_DRY_RUN false "$arg" ;;
        --delete) set_cli CLI_DELETE true "$arg" ;;
        --no-delete) set_cli CLI_DELETE false "$arg" ;;
        --update) set_cli CLI_UPDATE true "$arg" ;;
        --no-update) set_cli CLI_UPDATE false "$arg" ;;
        --verbose) set_cli CLI_VERBOSE true "$arg" ;;
        --no-verbose) set_cli CLI_VERBOSE false "$arg" ;;
        help | -h | --help)
            show_help
            exit 0
            ;;
        *)
            # Перший позиційний аргумент після напрямку — Host з ~/.ssh/config
            if [[ -n "$MODE" && "$arg" != -* ]]; then
                if [[ -z "$HOST" ]]; then
                    HOST="$arg"
                elif [[ "$HOST" == "$arg" ]]; then
                    echo "Попередження: host '$arg' вказано повторно."
                else
                    echo "Невідомий аргумент: $arg"
                    echo
                    show_help
                    exit 1
                fi
            else
                echo "Невідомий аргумент: $arg"
                echo
                show_help
                exit 1
            fi
            ;;
    esac
done

# Напрямок обовʼязковий (наприклад, якщо передали лише --dry-run)
if [[ -z "$MODE" ]]; then
    echo "Не вказано напрямок (push або pull)."
    echo
    show_help
    exit 1
fi

# ------------------------------- ПЕРЕВІРКИ -----------------------------------
command -v rsync >/dev/null || {
    echo "rsync не встановлено."
    exit 1
}
((${#PAIRS[@]} > 0)) || {
    echo "Список PAIRS порожній."
    exit 1
}

# Булеві налаштування мають бути строго true/false:
# інші значення ("yes", "1", "True") мовчки або небезпечно спотворюють поведінку
for v in "$PUSH_DELETE" "$PUSH_UPDATE" "$PUSH_DRY_RUN" \
    "$PULL_DELETE" "$PULL_UPDATE" "$PULL_DRY_RUN"; do
    [[ "$v" == true || "$v" == false ]] || {
        echo "Некоректне булеве значення: '$v' (дозволено тільки true/false)"
        exit 1
    }
done

# rsync -e передає команду ssh одним рядком, тому шлях до ключа з пробілом
# розібʼється на частини — такі шляхи відхиляємо одразу
if [[ "$SSH_KEY" =~ [[:space:]] ]]; then
    echo "SSH_KEY не може містити пробілів (обмеження rsync -e). Використайте ~/.ssh/config."
    exit 1
fi

# Символи, що ламають віддалену ssh-команду (mkdir/test у лапках)
BAD_CHARS="'\";"$'\n'
for entry in "${PAIRS[@]}"; do
    local_dir="${entry%%|*}"
    remote_dir="${entry#*|}"
    if [[ "$local_dir" == *'|'* || "$remote_dir" == *'|'* ]]; then
        echo "Пара містить '|' всередині шляху: $entry"
        exit 1
    fi
    if [[ "$remote_dir" == *["$BAD_CHARS"]* ]]; then
        echo "Віддалений шлях містить недопустимий символ (' \" ; або перенос рядка): $remote_dir"
        exit 1
    fi
done

# Блокування від паралельних запусків (наприклад, ручний запуск під час cron)
if command -v flock >/dev/null; then
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/sync_multi.lock"
    exec 9>"$LOCK_FILE"
    flock -n 9 || {
        echo "Інший запуск sync_multi ще триває."
        exit 1
    }
else
    echo "Попередження: flock не знайдено — перевірку паралельних запусків пропущено."
fi

# -------------------- ВИБІР ПАРАМЕТРІВ ЗАЛЕЖНО ВІД НАПРЯМКУ ------------------
if [[ "$MODE" == "push" ]]; then
    DELETE=$PUSH_DELETE
    UPDATE=$PUSH_UPDATE
    DRY_RUN=$PUSH_DRY_RUN
else
    DELETE=$PULL_DELETE
    UPDATE=$PULL_UPDATE
    DRY_RUN=$PULL_DRY_RUN
fi

# Аргументи командного рядка мають пріоритет над налаштуваннями у файлі
[[ -n "$CLI_DELETE" ]] && DELETE=$CLI_DELETE
[[ -n "$CLI_UPDATE" ]] && UPDATE=$CLI_UPDATE
[[ -n "$CLI_DRY_RUN" ]] && DRY_RUN=$CLI_DRY_RUN
[[ -n "$CLI_VERBOSE" ]] && VERBOSE=$CLI_VERBOSE

# ------------------------------- ПІДГОТОВКА ----------------------------------
# Базові ssh-опції; решта (порт, користувач, ключ) додається нижче
# В інтерактивному терміналі дозволено вхід по паролю (BatchMode вимкнено).
# Без терміналу (cron) — BatchMode=yes: пароль запитати ніде, і запуск
# без ключа просто завершиться помилкою замість зависання.
if [[ -t 0 || -t 1 ]]; then
    SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
else
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10
        -o StrictHostKeyChecking=accept-new)
fi
# Мультиплексування зʼєднання: пароль/ключ вводиться лише один раз,
# усі наступні ssh-виклики (mkdir, rsync кожної пари) перевикористовують канал
SSH_OPTS+=(-o ControlMaster=auto
    -o ControlPath="${XDG_RUNTIME_DIR:-/tmp}/ssh_sync_%r@%h-%p"
    -o ControlPersist=10m)

if [[ -n "$HOST" ]]; then
    # Host-аліас з ~/.ssh/config: User/Port/IdentityFile шукає сам ssh,
    # тому порт тут НЕ вказуємо (явний -p перекрив би значення з конфіга)
    REMOTE="$HOST"
    SSH_CMD=(ssh "${SSH_OPTS[@]}")
else
    REMOTE="${SERVER_USER}@${SERVER_HOST}"
    SSH_CMD=(ssh -p "$SERVER_PORT" "${SSH_OPTS[@]}")
fi

# Ключ (-i) — лише якщо SSH_KEY заданий; інакше використовується ssh-agent,
# налаштування з ~/.ssh/config або ключ за замовчуванням
if [[ -n "$SSH_KEY" ]]; then
    [[ -f "$SSH_KEY" ]] || {
        echo "Файл ключа не знайдено: $SSH_KEY"
        exit 1
    }
    SSH_CMD+=(-i "$SSH_KEY")
fi

# У cron (немає терміналу) пароль запитати ніде — без ключа автентифікація не пройде
if [[ -z "$SSH_KEY" ]] && ! { [[ -t 0 ]] || [[ -t 1 ]]; }; then
    echo "Попередження: запуск без терміналу (cron?) і SSH_KEY порожній — переконайтеся, що ключ задано в SSH_KEY або IdentityFile у ~/.ssh/config, інакше підключення не пройде." >&2
fi

# Базові опції rsync:
#   -a архівний режим (права, часи, рекурсія), -v докладно,
#   -h зрозумілі розміри, --partial докачка перерваних файлів
OPTS=(-avh --partial -e "${SSH_CMD[*]}")
for e in "${EXCLUDES[@]}"; do OPTS+=(--exclude="$e"); done
[[ "$DELETE" == true ]] && OPTS+=(--delete)   # дзеркальний режим
[[ "$UPDATE" == true ]] && OPTS+=(--update)   # пропускати файли, новіші в призначенні
[[ "$DRY_RUN" == true ]] && OPTS+=(--dry-run) # пробний запуск
# --progress лише в інтерактивному терміналі, щоб не засмічувати логи cron
[[ -t 1 ]] && OPTS+=(--progress)

# Перевірка SSH-зʼєднання один раз перед початком + визначення домашнього
# каталогу користувача на сервері (для розгортання ~ та $HOME у шляхах пар).
# stderr НЕ перехоплюємо: запит пароля й повідомлення ssh видно в терміналі.
# shellcheck disable=SC2016  # "$HOME" має бути літеральним — розгортається на сервері
REMOTE_HOME=$("${SSH_CMD[@]}" "$REMOTE" 'printf %s "$HOME"') || {
    echo "Немає зʼєднання з ${REMOTE} (перевірте ssh і ~/.ssh/config)." >&2
    exit 1
}
[[ -n "$REMOTE_HOME" ]] || {
    echo "Не вдалося визначити домашній каталог користувача на ${REMOTE}."
    exit 1
}

# ---------------- ВІДДАЛЕНІ ШЛЯХИ: ~ / $HOME -> абсолютний -------------------
# Розгортає префікс ~ або $HOME в абсолютний шлях домашнього каталогу
# на поточному сервері — тому пари однаково працюють із будь-яким хостом
# shellcheck disable=SC2016,SC2088  # ~ та $HOME тут навмисно літеральні
expand_remote_dir() {
    local d="$1"
    if [[ "$d" == "~" ]]; then
        d="$REMOTE_HOME"
    elif [[ "$d" == "~/"* ]]; then
        d="$REMOTE_HOME/${d#'~/'}"
    elif [[ "$d" == '$HOME' ]]; then
        d="$REMOTE_HOME"
    elif [[ "$d" == '$HOME/'* ]]; then
        d="$REMOTE_HOME/${d#'$HOME/'}"
    fi
    printf '%s' "$d"
}

for i in "${!PAIRS[@]}"; do
    PAIRS[i]="${PAIRS[i]%%|*}|$(expand_remote_dir "${PAIRS[i]#*|}")"
done

# -------------- ВІДДАЛЕНІ КАТАЛОГИ: один ssh-виклик на всі пари --------------
# Замість окремого ssh (mkdir/test) на кожну пару — один пакетний виклик.
declare -A MISSING_REMOTE=() # каталоги, яких немає на сервері
qargs=""
for entry in "${PAIRS[@]}"; do
    d="${entry#*|}"
    d="${d%/}"
    # невірну пару пропускаємо тут — sync_pair повідомить про неї окремо
    [[ -z "$d" || "$d" == "$entry" ]] && continue
    qargs+=" '$d'"
done
if [[ -n "$qargs" ]]; then
    if [[ "$MODE" == "push" && "$DRY_RUN" != true ]]; then
        "${SSH_CMD[@]}" "$REMOTE" "mkdir -p$qargs" || {
            echo "Не вдалося створити віддалені каталоги на ${REMOTE}."
            exit 1
        }
    else
        # push у dry-run або pull: тільки перевірка, без змін на сервері
        remote_out=$("${SSH_CMD[@]}" "$REMOTE" \
            "for d in$qargs; do test -d \"\$d\" || echo \"\$d\"; done") || {
            echo "Не вдалося перевірити віддалені каталоги на ${REMOTE}."
            exit 1
        }
        while IFS= read -r d; do
            [[ -n "$d" ]] && MISSING_REMOTE["$d"]=1
        done <<<"$remote_out"
    fi
fi
if ((${#MISSING_REMOTE[@]} > 0)); then
    if [[ "$MODE" == "pull" ]]; then
        echo "На сервері відсутні каталоги (відповідні пари буде пропущено): ${!MISSING_REMOTE[*]}"
    else
        echo "⚠ DRY-RUN: на сервері відсутні каталоги (реальний запуск створив би): ${!MISSING_REMOTE[*]}"
    fi
fi

# ------------------------- СИНХРОНІЗАЦІЯ ОДНІЄЇ ПАРИ -------------------------
sync_pair() {
    local idx="$1" entry="$2"
    local local_dir remote_dir src dst

    # Розбір рядка "локальна|віддалена"
    local_dir="${entry%%|*}"
    remote_dir="${entry#*|}"
    local_dir="${local_dir%/}" # прибрати кінцевий слеш
    remote_dir="${remote_dir%/}"

    if [[ -z "$local_dir" || -z "$remote_dir" || "$local_dir" == "$entry" ]]; then
        echo "Пара №$idx має невірний формат: $entry"
        return 1
    fi

    # Слеш наприкінці джерела = синхронізується ВМІСТ папки в папку призначення
    # Якщо локальна сторона — одиночний файл, синхронізується сам файл
    # (push -> файл у віддалений каталог, pull -> файл із нього назад)
    if [[ "$MODE" == "push" ]]; then
        if [[ -d "$local_dir" ]]; then
            src="${local_dir}/"
            dst="${REMOTE}:${remote_dir}/"
        elif [[ -f "$local_dir" ]]; then
            src="$local_dir"
            dst="${REMOTE}:${remote_dir}/"
        else
            echo "Локальної папки/файла немає: $local_dir"
            return 1
        fi
        # Про відсутні віддалені каталоги повідомляє пакетна перевірка перед циклом
    else
        if [[ -n "${MISSING_REMOTE["$remote_dir"]:-}" ]]; then
            echo "Папки на сервері немає: $remote_dir"
            return 1
        fi
        if [[ -f "$local_dir" ]]; then
            # Файл: тягнемо окремий файл із віддаленого каталогу (за тим самим імʼям)
            src="${REMOTE}:${remote_dir}/${local_dir##*/}"
            if [[ "$local_dir" == */* ]]; then
                dst="${local_dir%/*}/" # батьківський каталог локального файла
            else
                dst="./"
            fi
        else
            if [[ "$DRY_RUN" == true ]]; then
                # dry-run нічого не створює — лише попереджає
                [[ -d "$local_dir" ]] ||
                    echo "⚠ DRY-RUN: локальної папки немає: $local_dir (реальний запуск створив би її)"
            else
                mkdir -p "$local_dir" # створити, якщо немає
            fi
            src="${REMOTE}:${remote_dir}/"
            dst="${local_dir}/"
        fi
    fi

    if [[ "$VERBOSE" == true ]]; then
        echo "=============================================="
        echo "Пара №$idx [$MODE]  DELETE=$DELETE UPDATE=$UPDATE DRY_RUN=$DRY_RUN VERBOSE=$VERBOSE"
        echo "  $src  ->  $dst"
        echo "=============================================="
        rsync "${OPTS[@]}" "$src" "$dst"
        return $?
    fi

    # Тільки підсумок: вивід rsync показується лише якщо пара завершилась помилкою
    local out rc
    out=$(rsync "${OPTS[@]}" "$src" "$dst" 2>&1)
    rc=$?
    if ((rc == 0)); then
        echo "Пара №$idx: OK"
    else
        printf '%s\n' "$out"
        echo "✘ Пара №$idx: FAIL (код $rc)"
    fi
    return "$rc"
}

# ------------------------------ ГОЛОВНИЙ ЦИКЛ --------------------------------
OK=()
FAIL=()
for i in "${!PAIRS[@]}"; do
    n=$((i + 1))
    if sync_pair "$n" "${PAIRS[$i]}"; then
        OK+=("$n")
    else
        FAIL+=("$n") # помилка однієї пари не зупиняє решту
        # у режимі "тільки підсумок" sync_pair вже вивів "✘ Пара №N: FAIL"
        [[ "$VERBOSE" == true ]] && echo "✘ Пара №$n завершилась з помилкою."
    fi
    [[ "$VERBOSE" == true ]] && echo
done

# --------------------------------- ПІДСУМОК ----------------------------------
echo "================== ПІДСУМОК =================="
echo "Успішно:     ${OK[*]:-—}"
echo "З помилками: ${FAIL[*]:-—}"

# Код виходу: 0 — усе добре, 1 — була хоча б одна помилка (корисно для cron)
((${#FAIL[@]} == 0))
