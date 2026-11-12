#!/usr/bin/env bash
# =============================================================================
# sync_multi.sh — синхронізація ПК <-> СЕРВЕР через rsync (по SSH)
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

# --- Пари: "локальний_шлях|віддалений_шлях" — семантика rsync ---
# Скрипт обробляє ВСІ пари зі списку, по черзі.
# Слеш наприкінці ДЖЕРЕЛА (у push — локального шляху, у pull — віддаленого)
# означає "вміст папки", без слеша — "папку цілком", як у rsync:
#   "$HOME/Pictures|~/test"    -> ~/test/Pictures/... (папка цілком)
#   "$HOME/Pictures/|~/test"   -> файли безпосередньо в ~/test (вміст)
# Одиночний файл: віддалена сторона — ПОВНИЙ шлях до файла (з імʼям):
#   push -> файл створюється/перезаписується за цим шляхом,
#   pull -> файл за цим шляхом забирається назад у локальний шлях.
# Pull — ДЗЕРКАЛО push: повертає кожен шлях туди, звідки його взяв push:
#   папка цілком (без слеша): забирає remote_dir/імʼя_локальної_папки
#                             у батьківський каталог локального шляху;
#   вміст (зі слешем):        забирає вміст remote_dir у локальний каталог;
#   файл:                     забирає remote_dir у локальний шлях файла.
# Локальна сторона: "~" всередині значення НЕ розгортається (на відміну від
# віддаленої) — пишіть абсолютний шлях або "$HOME/...".
PAIRS=(
    "$HOME/Documents|~/test"
    "$HOME/Pictures|~/test"
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
  push:  DELETE=${PUSH_DELETE}  UPDATE=${PUSH_UPDATE}  DRY_RUN=${PUSH_DRY_RUN} VERBOSE=${VERBOSE}
  pull:  DELETE=${PULL_DELETE}  UPDATE=${PULL_UPDATE}  DRY_RUN=${PULL_DRY_RUN} VERBOSE=${VERBOSE}

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

# Символи, що ламають віддалену ssh-команду (mkdir/test у лапках).
# Перевіряємо ОБИДВІ сторони пари: у пакетних перевірках pull локальне
# імʼя (base) теж потрапляє в ssh-команду — апостроф у ньому ламає
# quoting для ВСІХ пар і може призвести до інʼєкції команди на сервері.
BAD_CHARS="'\";"$'\n'
for entry in "${PAIRS[@]}"; do
    local_dir="${entry%%|*}"
    remote_dir="${entry#*|}"
    if [[ "$local_dir" == *'|'* || "$remote_dir" == *'|'* ]]; then
        echo "Пара містить '|' всередині шляху: $entry"
        exit 1
    fi
    if [[ "$local_dir" == *["$BAD_CHARS"]* ]]; then
        echo "Локальний шлях містить недопустимий символ (' \" ; або перенос рядка): $local_dir"
        exit 1
    fi
    if [[ "$remote_dir" == *["$BAD_CHARS"]* ]]; then
        echo "Віддалений шлях містить недопустимий символ (' \" ; або перенос рядка): $remote_dir"
        exit 1
    fi
done

# Блокування від паралельних запусків (наприклад, ручний запуск під час cron)
if command -v flock >/dev/null; then
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/sync_multi.$(id -u).lock"
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
# усі наступні ssh-виклики (mkdir, rsync кожної пари) перевикористовують канал.
# uid у ControlPath — щоб сокет не конфліктував між користувачами машини
SSH_OPTS+=(-o ControlMaster=auto
    -o ControlPath="${XDG_RUNTIME_DIR:-/tmp}/ssh_sync_$(id -u)_%r@%h-%p"
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

# -------------- ВІДДАЛЕНІ ШЛЯХИ: один ssh-виклик на всі пари -----------------
# Замість окремого ssh (mkdir/test) на кожну пару — один пакетний виклик:
# менше мережевих звернень і один запит пароля (через ControlMaster).
#
# Хто створює шляхи:
#   Останній компонент віддаленого шляху (папку призначення чи сам файл)
#   rsync створює САМ, зі своїми правилами слеша. Скрипт готує лише
#   БАТЬКІВСЬКІ каталоги, щоб rsync не впав на відсутньому шляху.
declare -A MISSING_REMOTE=() # pull: відсутні віддалені шляхи (пару пропущено)
declare -A REMOTE_IS_FILE=() # pull: віддалений шлях — файл (файлова пара)
declare -A FOLDER_OK=()      # pull: папка-копія remote_dir/імʼя існує ("папка цілком")
qargs_mkdir=""               # батьківські каталоги для mkdir (реальний push)
qargs_dir=""                 # батьківські каталоги для перевірки test -d (dry-run push)
qargs_type=""                # pull: пари "віддалений_шлях|база" для визначення типу
for entry in "${PAIRS[@]}"; do
    local_dir="${entry%%|*}"
    d="${entry#*|}"
    d="${d%/}" # слеш наприкінці тут не потрібен: тип/каталог визначаємо без нього
    # невірну пару пропускаємо тут — sync_pair повідомить про неї окремо
    [[ -z "$d" || "$d" == "$entry" ]] && continue
    if [[ "$MODE" == "push" ]]; then
        # Батьківський каталог віддаленого шляху (для файла і папки однаково):
        # віддалений шлях "a/b" -> mkdir "a", а "b" створить rsync
        case "$d" in */*) parent="${d%/*}" ;; *) parent="" ;; esac
        if [[ -z "$parent" ]]; then
            continue # шлях у корені home — батьківський каталог і так існує
        elif [[ "$DRY_RUN" != true ]]; then
            qargs_mkdir+=" '$parent'" # реальний push: створюємо
        else
            qargs_dir+=" '$parent'" # dry-run: лише перевіряємо наявність
        fi
    else
        # pull: тип віддаленого шляху невідомий наперед; для пари "папка
        # цілком" треба також знати, чи існує папка-копія на сервері
        # (remote_dir/імʼя_локальної_папки). Пакуємо пару в один токен
        # "шлях|база" — база порожня для файлової пари (перевірки не потрібні)
        ld="${local_dir%/}"
        if [[ -f "$ld" ]]; then
            base=""
        else
            base="${ld##*/}"
        fi
        qargs_type+=" '$d|$base'"
    fi
done

if [[ -n "$qargs_mkdir" ]]; then
    "${SSH_CMD[@]}" "$REMOTE" "mkdir -p$qargs_mkdir" || {
        echo "Не вдалося створити віддалені каталоги на ${REMOTE}."
        exit 1
    }
fi
if [[ -n "$qargs_dir" ]]; then
    # push у dry-run: тільки перевірка, без змін на сервері
    remote_out=$("${SSH_CMD[@]}" "$REMOTE" \
        "for d in$qargs_dir; do test -d \"\$d\" || echo \"\$d\"; done") || {
        echo "Не вдалося перевірити віддалені каталоги на ${REMOTE}."
        exit 1
    }
    while IFS= read -r d; do
        [[ -n "$d" ]] && MISSING_REMOTE["$d"]=1
    done <<<"$remote_out"
fi
if [[ -n "$qargs_type" ]]; then
    # pull: для кожної пари — F (віддалений шлях = файл), DF (каталог, і
    # папка-копія d/база є), D (каталог, папки-копії немає), M (шляху немає)
    # shellcheck disable=SC2016  # \$d та \$b розгортаються на сервері
    remote_out=$("${SSH_CMD[@]}" "$REMOTE" \
        "for t in$qargs_type; do d=\${t%%|*}; b=\${t#*|}; if test -f \"\$d\"; then echo \"F \$d\"; elif test -d \"\$d\"; then if [ -n \"\$b\" ] && test -d \"\$d/\$b\"; then echo \"DF \$d\"; else echo \"D \$d\"; fi; else echo \"M \$d\"; fi; done") || {
        echo "Не вдалося перевірити віддалені шляхи на ${REMOTE}."
        exit 1
    }
    while IFS= read -r line; do
        case "$line" in
            F*) REMOTE_IS_FILE["${line#F }"]=1 ;;
            DF*) FOLDER_OK["${line#DF }"]=1 ;;
            D*) ;; # каталог є; папку-копію для "папки цілком" перевіряє sync_pair
            M*) MISSING_REMOTE["${line#M }"]=1 ;;
        esac
    done <<<"$remote_out"
fi
if ((${#MISSING_REMOTE[@]} > 0)); then
    if [[ "$MODE" == "pull" ]]; then
        echo "На сервері відсутні шляхи (відповідні пари буде пропущено): ${!MISSING_REMOTE[*]}"
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

    # Семантика rsync: слеш наприкінці ДЖЕРЕЛА означає "вміст папки",
    # без слеша — "папку цілком". У push джерело — локальна сторона,
    # тому її слеш передається rsync як є. У pull джерело обчислюється
    # з пари (дзеркало push), слеш віддаленої сторони не використовується.
    remote_dir="${remote_dir%/}" # далі працюємо зі шляхом без слеша

    if [[ -z "$local_dir" || -z "$remote_dir" || "$local_dir" == "$entry" ]]; then
        echo "Пара №$idx має невірний формат: $entry"
        return 1
    fi

    if [[ "$MODE" == "push" ]]; then
        # Джерело — локальна сторона: передаємо її rsync КАК Є (разом зі
        # слешем, якщо користувач його написав). Останній компонент
        # віддаленого шляху rsync створює сам (батьківські каталоги вже
        # готові пакетним mkdir перед циклом).
        if [[ -d "$local_dir" ]]; then
            src="$local_dir" # без слеша -> папка цілком, зі слешем -> вміст
            dst="${REMOTE}:${remote_dir}"
        elif [[ -f "$local_dir" ]]; then
            # У dry-run rsync НЕ створює батьківський каталог віддаленого
            # файла (на відміну від каталогу-призначення), тому пара з
            # відсутнім батьківським каталогом впала б помилково:
            # попереджаємо і пропускаємо (реальний запуск сам його створить)
            if [[ "$DRY_RUN" == true && -n "${MISSING_REMOTE["${remote_dir%/*}"]:-}" ]]; then
                echo "⚠ DRY-RUN: на сервері немає каталогу ${remote_dir%/*} (реальний запуск створив би його)"
                PAIR_SKIPPED=1 # пропущена пара — не зараховуємо як успіх
                return 0
            fi
            src="$local_dir"
            dst="${REMOTE}:${remote_dir}" # повний шлях до віддаленого файла
        else
            echo "Локальної папки/файла немає: $local_dir"
            return 1
        fi
        # Про відсутні віддалені шляхи повідомляє пакетна перевірка перед циклом
    else
        if [[ -n "${MISSING_REMOTE["$remote_dir"]:-}" ]]; then
            echo "На сервері немає: $remote_dir"
            return 1
        fi
        if [[ -n "${REMOTE_IS_FILE["$remote_dir"]:-}" ]]; then
            # Файлова пара: віддалена сторона — повний шлях до файла.
            # Повертаємо файл точно на локальне місце (дзеркало push).
            # Батьківський каталог міг бути видалений разом із файлом
            # (типовий сценарій відновлення) — створюємо його
            ld="${local_dir%/}"
            if [[ "$DRY_RUN" == true ]]; then
                if [[ "$ld" == */* && ! -d "${ld%/*}" ]]; then
                    echo "⚠ DRY-RUN: локальної папки немає: ${ld%/*} (реальний запуск створив би її)"
                fi
            else
                [[ "$ld" == */* ]] && mkdir -p "${ld%/*}"
            fi
            src="${REMOTE}:${remote_dir}"
            dst="$local_dir"
        elif [[ "$local_dir" == */ ]]; then
            # Вміст (локальна сторона зі слешем): тягнемо ВМІСТ віддаленого
            # каталогу назад у локальний каталог (дзеркало push зі слешем)
            if [[ "$DRY_RUN" == true ]]; then
                # dry-run нічого не створює — лише попереджає
                [[ -d "${local_dir%/}" ]] ||
                    echo "⚠ DRY-RUN: локальної папки немає: $local_dir (реальний запуск створив би її)"
            else
                mkdir -p "${local_dir%/}" # створити, якщо немає
            fi
            src="${REMOTE}:${remote_dir}/"
            dst="${local_dir%/}/"
        else
            # Папка цілком (без слеша): push rsync ЗАВЖДИ вкладає папку
            # всередину призначення (remote_dir/імʼя), навіть якщо призначення
            # ще не існувало (перевірено на rsync 3.5: "src dst" -> dst/src/).
            # Тому pull бере звідти й кладе у батьківський каталог локального
            # шляху — папка відновлюється точно на своєму місці.
            ld="${local_dir%/}"
            base="${ld##*/}"
            if [[ -z "${FOLDER_OK["$remote_dir"]:-}" ]]; then
                echo "На сервері немає: ${remote_dir}/${base} (push не робився або папку видалено)"
                return 1
            fi
            src="${REMOTE}:${remote_dir}/${base}"
            if [[ "$DRY_RUN" == true ]]; then
                # dry-run нічого не створює — лише попереджає
                if [[ "$ld" == */* && ! -d "${ld%/*}" ]]; then
                    echo "⚠ DRY-RUN: локальної папки немає: ${ld%/*} (реальний запуск створив би її)"
                fi
            else
                [[ "$ld" == */* ]] && mkdir -p "${ld%/*}" # батьківський каталог
            fi
            if [[ "$ld" == */* ]]; then
                dst="${ld%/*}/"
            else
                dst="./"
            fi
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
SKIPPED=()
PAIR_SKIPPED=0 # sync_pair ставить 1, якщо пару пропущено (наприклад, у dry-run)
for i in "${!PAIRS[@]}"; do
    n=$((i + 1))
    PAIR_SKIPPED=0
    if sync_pair "$n" "${PAIRS[$i]}"; then
        if ((PAIR_SKIPPED == 1)); then
            SKIPPED+=("$n") # пропущена пара — не успіх і не помилка
        else
            OK+=("$n")
        fi
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
echo "Пропущено:   ${SKIPPED[*]:-—}"
echo "З помилками: ${FAIL[*]:-—}"

# Код виходу: 0 — усе добре, 1 — була хоча б одна помилка (корисно для cron)
((${#FAIL[@]} == 0))
