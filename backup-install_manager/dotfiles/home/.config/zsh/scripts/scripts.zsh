mkcd() {
    mkdir -p -- "$1" && cd -P -- "$1"
}

ex() {
    local archive
    local target_dir
    # Перевірка аргументів
    if (($# == 0 || $# > 2)); then
        printf 'Використання: ex <архів> [папка]\n'
        return 1
    fi
    archive="$1"
    target_dir="${2:-.}"
    # Перевірка існування архіву
    if [[ ! -f "$archive" ]]; then
        printf 'Помилка: файл не знайдено: %s\n' "$archive"
        return 1
    fi
    # Створення папки призначення
    if [[ ! -d "$target_dir" ]]; then
        printf 'Створення папки: %s\n' "$target_dir"
        if ! mkdir -p -- "$target_dir"; then
            printf 'Помилка: не вдалося створити папку: %s\n' "$target_dir"
            return 1
        fi
    fi
    # Інформація
    printf 'Архів:  %s\n' "$archive"
    printf 'Папка:  %s\n' "$target_dir"
    printf '\n'
    # Визначення типу архіву
    case "${archive:l}" in
        # TAR
        *.tar)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -xf "$archive" -C "$target_dir"
            ;;
        # TAR.GZ / TGZ
        *.tar.gz | *.tgz)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -xzf "$archive" -C "$target_dir"
            ;;
        # TAR.BZ2 / TBZ / TBZ2
        *.tar.bz2 | *.tbz | *.tbz2)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -xjf "$archive" -C "$target_dir"
            ;;
        # TAR.XZ / TXZ
        *.tar.xz | *.txz)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -xJf "$archive" -C "$target_dir"
            ;;
        # TAR.ZST / TZST
        *.tar.zst | *.tzst)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar --zstd -xf "$archive" -C "$target_dir"
            ;;
        # ZIP
        *.zip)
            if ! command -v unzip >/dev/null 2>&1; then
                printf 'Помилка: команда unzip не знайдена\n'
                printf 'Встановлення: sudo pacman -S --needed unzip\n'
                return 1
            fi
            unzip "$archive" -d "$target_dir"
            ;;
        # 7Z
        *.7z)
            if ! command -v 7z >/dev/null 2>&1; then
                printf 'Помилка: команда 7z не знайдена\n'
                printf 'Встановлення: sudo pacman -S --needed 7zip\n'
                return 1
            fi
            7z x "$archive" "-o$target_dir"
            ;;
        # RAR
        *.rar)
            if command -v bsdtar >/dev/null 2>&1; then
                bsdtar -xf "$archive" -C "$target_dir"
            elif command -v 7z >/dev/null 2>&1; then
                7z x "$archive" "-o$target_dir"
            else
                printf 'Помилка: для RAR потрібен bsdtar або 7z\n'
                printf 'Встановлення:\n'
                printf '  sudo pacman -S --needed libarchive 7zip\n'
                return 1
            fi
            ;;
        # GZIP
        # Наприклад:
        #   database.sql.gz
        # Результат:
        #   target_dir/database.sql
        *.gz)
            if ! command -v gzip >/dev/null 2>&1; then
                printf 'Помилка: команда gzip не знайдена\n'
                return 1
            fi
            local output_name
            output_name="${archive:t:r}"
            gzip -dc -- "$archive" >"$target_dir/$output_name"
            ;;
        # BZIP2
        *.bz2)
            if ! command -v bzip2 >/dev/null 2>&1; then
                printf 'Помилка: команда bzip2 не знайдена\n'
                return 1
            fi
            local output_name
            output_name="${archive:t:r}"
            bzip2 -dc -- "$archive" >"$target_dir/$output_name"
            ;;
        # XZ
        *.xz)
            if ! command -v xz >/dev/null 2>&1; then
                printf 'Помилка: команда xz не знайдена\n'
                return 1
            fi
            local output_name
            output_name="${archive:t:r}"
            xz -dc -- "$archive" >"$target_dir/$output_name"
            ;;
        # Невідомий формат
        # Пробуємо універсальний bsdtar.
        *)
            if command -v bsdtar >/dev/null 2>&1; then
                printf 'Невідоме розширення. Пробую bsdtar...\n'
                if ! bsdtar -xf "$archive" -C "$target_dir"; then
                    printf 'Помилка: формат архіву не підтримується\n'
                    return 1
                fi
            else
                printf 'Помилка: невідомий формат архіву: %s\n' "$archive"
                printf 'Спробуй встановити libarchive:\n'
                printf '  sudo pacman -S --needed libarchive\n'
                return 1
            fi
            ;;
    esac
    # Перевірка результату
    local exit_code=$?
    if ((exit_code != 0)); then
        printf '\nПомилка: не вдалося розпакувати архів\n'
        return "$exit_code"
    fi
    printf '\nГотово.\n'
    printf 'Розпаковано в: %s\n' "$target_dir"
}

pk() {
    local archive
    local -a sources
    # Перевірка аргументів
    if (($# < 2)); then
        printf 'Використання: pk <архів> <файл/папка> [ще файл/папка ...]\n'
        return 1
    fi
    archive="$1"
    shift
    sources=("$@")
    # Перевірка джерел
    local source
    for source in "${sources[@]}"; do
        if [[ ! -e "$source" ]]; then
            printf 'Помилка: файл або папку не знайдено: %s\n' "$source"
            return 1
        fi
    done
    # Перевірка існування архіву
    if [[ -e "$archive" ]]; then
        printf 'Помилка: файл уже існує: %s\n' "$archive"
        return 1
    fi
    # Створення батьківської папки для архіву
    local archive_dir
    archive_dir="${archive:h}"
    if [[ "$archive_dir" != "." && ! -d "$archive_dir" ]]; then
        printf 'Створення папки: %s\n' "$archive_dir"
        if ! mkdir -p -- "$archive_dir"; then
            printf 'Помилка: не вдалося створити папку: %s\n' "$archive_dir"
            return 1
        fi
    fi
    # Інформація
    printf 'Створення архіву:\n'
    printf '  %s\n' "$archive"
    printf 'Джерела:\n'
    for source in "${sources[@]}"; do
        printf '  %s\n' "$source"
    done
    printf '\n'
    # Визначення типу архіву
    case "${archive:l}" in
        # TAR
        *.tar)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -cf "$archive" -- "${sources[@]}"
            ;;
        # TAR.GZ
        *.tar.gz | *.tgz)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -czf "$archive" -- "${sources[@]}"
            ;;
        # TAR.BZ2
        *.tar.bz2 | *.tbz | *.tbz2)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -cjf "$archive" -- "${sources[@]}"
            ;;
        # TAR.XZ
        *.tar.xz | *.txz)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            tar -cJf "$archive" -- "${sources[@]}"
            ;;
        # TAR.ZST
        *.tar.zst | *.tzst)
            if ! command -v tar >/dev/null 2>&1; then
                printf 'Помилка: команда tar не знайдена\n'
                return 1
            fi
            if ! command -v zstd >/dev/null 2>&1; then
                printf 'Помилка: команда zstd не знайдена\n'
                printf 'Встановлення: sudo pacman -S --needed zstd\n'
                return 1
            fi
            tar --zstd -cf "$archive" -- "${sources[@]}"
            ;;
        # ZIP
        *.zip)
            if ! command -v zip >/dev/null 2>&1; then
                printf 'Помилка: команда zip не знайдена\n'
                printf 'Встановлення: sudo pacman -S --needed zip\n'
                return 1
            fi
            zip -r "$archive" -- "${sources[@]}"
            ;;
        # 7Z
        *.7z)
            if ! command -v 7z >/dev/null 2>&1; then
                printf 'Помилка: команда 7z не знайдена\n'
                printf 'Встановлення: sudo pacman -S --needed 7zip\n'
                return 1
            fi
            7z a "$archive" -- "${sources[@]}"
            ;;
        # Невідомий формат
        *)
            printf 'Помилка: формат архіву не підтримується:\n'
            printf '  %s\n' "$archive"
            printf '\n'
            printf 'Підтримуються:\n'
            printf '  .tar\n'
            printf '  .tar.gz / .tgz\n'
            printf '  .tar.bz2 / .tbz / .tbz2\n'
            printf '  .tar.xz / .txz\n'
            printf '  .tar.zst / .tzst\n'
            printf '  .zip\n'
            printf '  .7z\n'
            return 1
            ;;
    esac
    # Перевірка результату
    local exit_code=$?
    if ((exit_code != 0)); then
        printf '\nПомилка: не вдалося створити архів\n'
        return "$exit_code"
    fi
    printf '\nГотово.\n'
    printf 'Створено: %s\n' "$archive"
}
