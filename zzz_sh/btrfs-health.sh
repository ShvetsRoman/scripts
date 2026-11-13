#!/usr/bin/env bash
# ==============================================================================
# Скрипт діагностики та обслуговування файлової системи Btrfs і знімків Snapper
# Призначений для Arch Linux із завантажувачем GRUB
# Використання: ./btrfs-health.sh [--dry-run] [--keep N]
# ==============================================================================

# Суворий режим виконання:
# -E : успадкування пасток помилок (ERR) у функціях та підпроцесах
# -e : негайне завершення скрипта при будь-якій ненульовій помилці команди
# -u : помилка при зверненні до неініціалізованої змінної
# -o pipefail : конвеєр (pipe) повертає код помилки першої невдалої команди
set -Eeuo pipefail

# Кількість останніх знімків, які потрібно залишати для кожної конфігурації.
# Ліміти з /etc/snapper/configs/* ігноруються — діє лише це значення.
KEEP=10

# Режим "сухого прогону" (1 = лише перевірка без видалення знімків і балансування)
DRY_RUN=0

# Список конфігурацій Snapper для перевірки та очищення
CONFIGS=(root home)

# Поріг нерозподіленого простору (Unallocated) у байтах — 15 GiB.
# Балансування (balance) запуститься ТІЛЬКИ якщо нерозподіленого місця менше,
# щоб не зношувати комірки пам'яті NVMe SSD зайвими перезаписами.
MIN_UNALLOCATED=$((15 * 1024 * 1024 * 1024))

# --- Розбір аргументів командного рядка ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --keep)
            [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]] || {
                echo "Помилка: --keep вимагає число" >&2
                exit 1
            }
            KEEP="$2"
            shift 2
            ;;
        -h | --help)
            echo "Використання: $(basename "$0") [--dry-run] [--keep N]"
            echo "  --dry-run   Перевірка стану без видалення знімків та балансування"
            echo "  --keep N    Залишити N останніх знімків (за замовчуванням: $KEEP)"
            exit 0
            ;;
        *)
            echo "Невідомий аргумент: $1" >&2
            exit 1
            ;;
    esac
done

# --- Допоміжні функції виводу ---
color() {
    local c=0
    case "$1" in
        red) c=31 ;;    # Критичні помилки та збої диска
        green) c=32 ;;  # Заголовки етапів та успішні статуси
        yellow) c=33 ;; # Попередження та рекомендації
        blue) c=34 ;;   # Інформаційні повідомлення
    esac
    printf '\n\033[%sm%s\033[0m\n' "$c" "$2"
}

die() {
    color red "ПОМИЛКА: $*" >&2
    exit 1
}

# --- 1. Перевірка та підвищення прав доступу (sudo) ---
# Використовуємо realpath, щоб коректно перезапустити скрипт незалежно від поточної папки
if [[ $EUID -ne 0 ]]; then
    SCRIPT_PATH="$(realpath "$0")"
    exec sudo "$SCRIPT_PATH" "$@"
fi

# --- 2. Перевірка наявності необхідних утиліт та типу ФС ---
for cmd in btrfs snapper findmnt flock; do
    command -v "$cmd" >/dev/null 2>&1 || die "Не знайдено необхідну утиліту: $cmd"
done

[[ "$(findmnt -no FSTYPE /)" == "btrfs" ]] || die "Кореневий розділ (/) не використовує Btrfs"

# --- 3. Захист від одночасного запуску двох копій скрипта ---
exec 9>/var/lock/btrfs-health.lock
flock -n 9 || die "Скрипт уже виконується в іншому вікні або фоновому процесі"

color green "=== BTRFS + SNAPPER HEALTH CHECK (KEEP=$KEEP) $( ((DRY_RUN)) && echo '[DRY-RUN]') ==="

# --- 4. Перевірка апаратних помилок I/O та пошкоджень метаданих ---
color green "[1] Лічильники помилок накопичувача (device stats)"
STATS_OUT="$(btrfs device stats /)"
echo "$STATS_OUT"

# Усі лічильники мають закінчуватися на '0'. Якщо ні — є проблеми з SSD або контролером
if echo "$STATS_OUT" | grep -vqE '\s0$'; then
    color red "УВАГА: Виявлено помилки читання/запису або пошкодження даних на диску!"
fi

# --- 5. Загальний звіт про використання простору Btrfs ---
color green "[2] Розподіл простору файлової системи"
btrfs filesystem usage /

# --- 6. Перевірка цілісності даних (scrub) та підтримки SSD (TRIM) ---
color green "[3] Стан перевірки цілісності (scrub) та TRIM"
btrfs scrub status / || true

if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
    color blue "fstrim.timer: увімкнено (оптимально для здоров'я NVMe SSD)"
else
    color yellow "fstrim.timer: вимкнено (рекомендується: sudo systemctl enable --now fstrim.timer)"
fi

# --- 7. Функція примусового очищення знімків із лімітом KEEP ---
cleanup_config() {
    local cfg="$1"

    # Перевіряємо, чи існує конфігурація в Snapper
    if ! snapper -c "$cfg" get-config >/dev/null 2>&1; then
        color yellow "Конфігурацію '$cfg' не знайдено, пропускаю"
        return 0
    fi

    color green "[4] Поточні знімки ($cfg):"
    snapper -c "$cfg" list

    # Отримуємо відсортований за зростанням список усіх ID знімків, крім '0' (поточний стан)
    # --csvout та --columns number гарантують точне зчитування без залежності від локалі та форматування таблиці
    mapfile -t ALL_IDS < <(
        snapper --csvout -c "$cfg" list --columns number |
            tail -n +2 |
            grep -v '^0$' |
            sort -n
    )

    local total=${#ALL_IDS[@]}
    if ((total <= KEEP)); then
        color blue "Для '$cfg' знайдено $total знімків (ліміт KEEP=$KEEP). Видалення не потрібне."
        return 0
    fi

    # Вираховуємо, скільки найстаріших знімків потрібно видалити
    local to_delete_count=$((total - KEEP))
    local ids_to_delete=("${ALL_IDS[@]:0:to_delete_count}")

    color yellow "Для '$cfg' знайдено $total знімків. Буде видалено старіші ($to_delete_count шт.): ${ids_to_delete[*]}"

    if ((DRY_RUN)); then
        color yellow "[dry-run] snapper -c $cfg delete ${ids_to_delete[*]}"
        return 0
    fi

    # Видаляємо застарілі знімки одним пакетним викликом
    snapper -c "$cfg" delete "${ids_to_delete[@]}"
}

for cfg in "${CONFIGS[@]}"; do
    cleanup_config "$cfg"
done

# --- 8. Синхронізація фонового видалення підтомів ---
# Btrfs видаляє дані знімків асинхронно у фоні. Ця команда чекає завершення процесу,
# щоб у підсумку побачити реальний обсяг звільненого місця.
if ((! DRY_RUN)); then
    color green "[5] Очікування завершення фонового очищення підтомів..."
    btrfs subvolume sync /
fi

# --- 9. Умовне інкрементальне балансування (balance) ---
# Перевіряємо розмір нерозподіленого простору (Unallocated) у байтах
color green "[6] Оцінка потреби у балансуванні чанків (balance)"
UNALLOCATED_BYTES="$(btrfs filesystem usage -b / | awk '/Unallocated:/ {getline; print $2}')"

if [[ -n "$UNALLOCATED_BYTES" ]] && ((UNALLOCATED_BYTES < MIN_UNALLOCATED)); then
    color yellow "Нерозподіленого місця менше 15 GiB. Запускаю обережний balance..."
    # Перепаковуємо лише майже порожні чанки (заповнені на 5%, 10%, 20%),
    # не чіпаючи щільно заповнені блоки даних
    for u in 5 10 20; do
        if ((DRY_RUN)); then
            color yellow "[dry-run] btrfs balance start -dusage=$u -musage=5 /"
        else
            btrfs balance start -dusage="$u" -musage=5 / || color yellow "balance usage=$u пропущено"
        fi
    done
else
    color blue "Нерозподіленого місця достатньо. Balance не потрібен (бережемо ресурс SSD)."
fi

# --- 10. Перевірка інтеграції з GRUB (grub-btrfsd) ---
# Демон grub-btrfsd автоматично оновлює меню завантаження GRUB при створенні або видаленні знімків
color green "[7] Перевірка служби меню завантаження (grub-btrfsd)"
if [[ "$(systemctl show -p LoadState --value grub-btrfsd.service 2>/dev/null)" == "loaded" ]]; then
    if systemctl is-active --quiet grub-btrfsd.service; then
        color blue "grub-btrfsd: активний (знімки автоматично додаються в GRUB)"
    else
        color yellow "grub-btrfsd: встановлений, але НЕ запущений (увімкніть: sudo systemctl enable --now grub-btrfsd.service)"
    fi
else
    color yellow "grub-btrfsd: не встановлений (для завантаження зі знімків у GRUB встановіть пакет 'grub-btrfs')"
fi

# --- 11. Фінальний звіт ---
color green "[Підсумок після обслуговування]"
btrfs filesystem usage /
color green "=== ГОТОВО ==="
