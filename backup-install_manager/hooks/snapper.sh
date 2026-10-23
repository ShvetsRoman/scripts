#!/usr/bin/env bash
# Логіка hook; середовище надає src/hooks/hook_runtime.sh.
hook_main() {
    # Hooks модуля snapper.
    _snapper_root() {
        if (( EUID == 0 )); then
            "$@"
        else
            command -v sudo >/dev/null 2>&1 || { log error 'Snapper: sudo не знайдено'; return 2; }
            sudo -- "$@"
        fi
    }

    # Missing prerequisites are an expected SKIP (return 0), real command failures are errors.
    _snapper_ready() {
        local fs
        for cmd in findmnt snapper systemctl pacman; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                log warn "Snapper: немає команди $cmd — [SKIP]"
                return 1
            fi
        done
        fs="$(findmnt -n -o FSTYPE /)" || return 2
        if [[ "$fs" != btrfs ]]; then
            log warn 'Snapper: / не на Btrfs — [SKIP]'
            return 1
        fi
        if ! _snapper_root test -f /etc/snapper/configs/root; then
            log warn 'Snapper: /etc/snapper/configs/root відсутній — [SKIP]'
            return 1
        fi
        if ! _snapper_root test -f /etc/snapper/configs/home; then
            log warn 'Snapper: /etc/snapper/configs/home відсутній — [SKIP]'
            return 1
        fi
        return 0
    }

    _snapper_status() {
        local config
        for config in root home; do
            log info "Snapper $config:"
            _snapper_root snapper -c "$config" get-config || return 1
        done
        _snapper_root systemctl list-timers --all snapper-timeline.timer snapper-cleanup.timer --no-pager || return 1
        _snapper_root systemctl is-active grub-btrfsd.service || true
    }

    _snapper_execute() {
        local ready=0 override_file override_dir expected current
        override_dir=/etc/systemd/system/snapper-timeline.timer.d
        override_file="$override_dir/override.conf"
        expected=$'[Timer]\nOnCalendar=\nOnCalendar=*-*-* 00,06,12,18:00:00\n'

        if [[ "${DRY_RUN:-false}" == true ]]; then
            log info 'Snapper: [DRY-RUN] перевірка root/home, backup, політики та таймер 6 годин'
            return 0
        fi

        _snapper_ready || ready=$?
        case "$ready" in
            0) ;;
            1) log info '[SKIP] Snapper: налаштування пропущено, Setup Manager продовжує роботу'; return 0 ;;
            *) log error 'Snapper: помилка перевірки передумов'; return 2 ;;
        esac

        _snapper_root snapper -c root set-config \
            TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
            TIMELINE_LIMIT_HOURLY=4 TIMELINE_LIMIT_DAILY=7 \
            TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=3 \
            TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
            NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=3 || return 1

        _snapper_root snapper -c home set-config \
            TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
            TIMELINE_LIMIT_HOURLY=4 TIMELINE_LIMIT_DAILY=5 \
            TIMELINE_LIMIT_WEEKLY=3 TIMELINE_LIMIT_MONTHLY=2 \
            TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
            NUMBER_CLEANUP=yes NUMBER_LIMIT=5 NUMBER_LIMIT_IMPORTANT=3 || return 1

        _snapper_root install -d -m 0755 -- "$override_dir" || return 1
        # Do not overwrite an unchanged timer override.
        current="$(_snapper_root cat -- "$override_file" 2>/dev/null)" || current=''
        if [[ "$current" != "${expected%$'\n'}" ]]; then
            printf '%s' "$expected" | _snapper_root tee "$override_file" >/dev/null || return 1
            _snapper_root systemctl daemon-reload || return 1
        fi
        _snapper_root systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || return 1
        _snapper_root systemctl restart snapper-timeline.timer || return 1
        # grub-btrfsd потрібен лише коли встановлено та використовується GRUB.
        if command -v grub-install >/dev/null 2>&1 && \
           [[ -f /boot/grub/grub.cfg || -f /boot/grub2/grub.cfg ]]; then
            _snapper_root systemctl enable --now grub-btrfsd.service || return 1
        else
            log info '[SKIP] grub-btrfsd: GRUB не виявлено'
        fi
        log ok 'Snapper: root/home та таймер 6 годин налаштовано'
        return 0
    }
    _snapper_execute
}
