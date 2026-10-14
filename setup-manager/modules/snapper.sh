#!/usr/bin/env bash
# shellcheck disable=SC2034

MODULE_ID="snapper"
MODULE_TITLE="Snapper snapshots"
MODULE_ORDER=85

PACMAN_PACKAGES=(snapper snap-pac grub-btrfs)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=()

hook_snapper() {
    local config
    local override_dir=/etc/systemd/system/snapper-timeline.timer.d

    # Немає Btrfs або готових конфігурацій — пропускаємо без помилки.
    if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" != btrfs ]]; then
        log warn '[SKIP] Snapper: корінь системи не на Btrfs'
        return 0
    fi

    for config in root home; do
        if [[ ! -f "/etc/snapper/configs/$config" ]]; then
            log warn "[SKIP] Snapper: конфігурація $config відсутня"
            return 0
        fi
    done

    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info '[DRY-RUN] Snapper: root/home і таймер 6 годин'
        return 0
    fi

    # Правила зберігання snapshot для root.
    sudo snapper -c root set-config \
        TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
        TIMELINE_LIMIT_HOURLY=4 TIMELINE_LIMIT_DAILY=7 \
        TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=3 \
        TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
        NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=3 || return 1

    # Правила зберігання snapshot для home.
    sudo snapper -c home set-config \
        TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
        TIMELINE_LIMIT_HOURLY=4 TIMELINE_LIMIT_DAILY=5 \
        TIMELINE_LIMIT_WEEKLY=3 TIMELINE_LIMIT_MONTHLY=2 \
        TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
        NUMBER_CLEANUP=yes NUMBER_LIMIT=5 NUMBER_LIMIT_IMPORTANT=3 || return 1

    # Snapshot кожні 6 годин (root і home через спільний таймер).
    sudo install -d -m 0755 -- "$override_dir" || return 1
    printf '[Timer]\nOnCalendar=\nOnCalendar=*-*-* 00,06,12,18:00:00\n' |
        sudo tee "$override_dir/override.conf" >/dev/null || return 1

    sudo systemctl daemon-reload || return 1
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || return 1
    sudo systemctl restart snapper-timeline.timer || return 1
    sudo systemctl enable --now grub-btrfsd.service || return 1

    log ok "Snapper: root/home налаштовано, таймер кожні 6 годин"
}
