#!/usr/bin/env bash
set -Eeuo pipefail

KEEP=10
DRY_RUN=0
CONFIGS=(root home)

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

color() {
    local c
    case "$1" in
        red) c=31 ;;
        yellow) c=33 ;;
        green) c=32 ;;
        *) c=0 ;;
    esac
    printf '\n\033[%sm%s\033[0m\n' "$c" "$2"
}

die() {
    color red "$*"
    exit 1
}

# --- Перевірки ---
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
for cmd in btrfs snapper findmnt; do
    command -v "$cmd" >/dev/null || die "Не знайдено: $cmd"
done
[[ "$(findmnt -no FSTYPE /)" == "btrfs" ]] || die "/ не є Btrfs"

exec 9>/var/lock/btrfs-health.lock
flock -n 9 || die "Скрипт уже запущено"

color green "=== BTRFS + SNAPPER HEALTH CHECK ==="

color green "[1] Використання диска"
btrfs filesystem usage /
btrfs device stats /

color green "[2] Стан scrub"
btrfs scrub status / || true

# --- Очищення снапшотів ---
cleanup_config() {
    local cfg="$1"

    if ! snapper -c "$cfg" get-config >/dev/null 2>&1; then
        color yellow "Конфіг '$cfg' не знайдено, пропускаю"
        return 0
    fi

    color green "Снапшоти ($cfg):"
    snapper -c "$cfg" list

    # Використовуємо власні алгоритми snapper, які поважають pre/post-пари,
    # important-прапорець та ліміти з /etc/snapper/configs/$cfg
    if ((DRY_RUN)); then
        color yellow "[dry-run] snapper -c $cfg cleanup number"
        return 0
    fi

    snapper -c "$cfg" cleanup number
    snapper -c "$cfg" cleanup timeline
    snapper -c "$cfg" cleanup empty-pre-post
}

for cfg in "${CONFIGS[@]}"; do
    cleanup_config "$cfg"
done

# --- Чекаємо фонового звільнення місця ---
if ((! DRY_RUN)); then
    color green "Синхронізація видалених subvolume..."
    btrfs subvolume sync /
fi

# --- Інкрементальний balance ---
color green "Balance (обережний режим)"
for u in 5 10 20; do
    if ((DRY_RUN)); then
        color yellow "[dry-run] balance -dusage=$u"
    else
        btrfs balance start -dusage="$u" / || color yellow "balance usage=$u не виконано"
    fi
done

# --- grub-btrfsd ---
color green "grub-btrfsd"
if systemctl list-unit-files grub-btrfsd.service >/dev/null 2>&1; then
    systemctl is-active --quiet grub-btrfsd.service &&
        color green "активний" ||
        color yellow "встановлений, але не активний"
else
    color yellow "не встановлений"
fi

color green "[Підсумок]"
btrfs filesystem usage /
color green "=== ГОТОВО ==="
