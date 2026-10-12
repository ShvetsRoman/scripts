#!/usr/bin/env bash
# Git керує лише коренем репозиторію Setup Manager.
git_main() {
    local action="${1:-status}"
    command -v git >/dev/null || { log_error 'Git не встановлено'; return 1; }
    case "$action" in
        init)
            if [[ "${DRY_RUN:-false}" == true ]]; then log_info '[DRY-RUN] git init'; return 0; fi
            git -C "$ROOT_DIR" init ;;
        status|log|diff)
            git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { log_error 'Git-репозиторій не ініціалізовано'; return 1; }
            case "$action" in
                status) git -C "$ROOT_DIR" status --short ;;
                log) git -C "$ROOT_DIR" log --oneline -10 ;;
                diff) git -C "$ROOT_DIR" diff -- ;;
            esac ;;
        commit)
            [[ -n "${2:-}" ]] || { log_error 'Вкажи повідомлення коміту'; return 2; }
            if [[ "${DRY_RUN:-false}" == true ]]; then log_info "[DRY-RUN] git commit: $2"; return 0; fi
            # Умисно не робимо git add .: користувач обирає файли сам.
            git -C "$ROOT_DIR" commit -m "$2" ;;
        *) log_error 'git init|status|log|diff|commit ПОВІДОМЛЕННЯ'; return 2 ;;
    esac
}
