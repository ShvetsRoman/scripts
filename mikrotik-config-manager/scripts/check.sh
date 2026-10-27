#!/usr/bin/env bash
# Перевірка Rust-проєкту з кольоровим виводом і незмінно чистим TXT-звітом.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_FILE="${REPORT_FILE:-$HOME/Documents/mikrotik-config-manager-check.txt}"
LOG_FILE="$(mktemp)"
# Версію визначаємо за Cargo.toml без дублювання чисел у Bash.
PROJECT_VERSION="$(awk '
    /^\[package\]$/ { package=1; next }
    /^\[/ { package=0 }
    package && /^[[:space:]]*version[[:space:]]*=/ {
        sub(/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/, "")
        sub(/"[[:space:]]*$/, "")
        print
        exit
    }' "$ROOT/Cargo.toml")"
if [[ -z "$PROJECT_VERSION" ]]; then
    printf '[ERROR] У Cargo.toml відсутня версія пакета\n' >&2
    exit 2
fi
trap 'rm -f -- "$LOG_FILE"' EXIT

# Відсутність каталогу звіту — явна помилка, без прихованого створення каталогів.
if [[ ! -d "$(dirname -- "$REPORT_FILE")" ]]; then
    printf '[ERROR] Каталог звіту не існує: %s\n' "$(dirname -- "$REPORT_FILE")" >&2
    exit 2
fi
if ! : > "$REPORT_FILE"; then
    printf '[ERROR] Неможливо записати звіт: %s\n' "$REPORT_FILE" >&2
    exit 2
fi

COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then COLOR=1; fi
now() { date +%s; }
start="$(now)"
pass=0; fail=0; skip=0
rust_pass=0; rust_fail=0; rust_ignored=0
STEPS=(); STATES=(); DURATIONS=()

emit() {
    local line="$1" code="${2:-}"
    if (( COLOR )) && [[ -n "$code" ]]; then
        printf '\033[%sm%s\033[0m\n' "$code" "$line"
    else
        printf '%s\n' "$line"
    fi
    printf '%s\n' "$line" >> "$REPORT_FILE"
}

run_stage() {
    local name="$1"; shift
    local began="$(now)" result=0
    : > "$LOG_FILE"
    (cd "$ROOT" && "$@") > "$LOG_FILE" 2>&1 || result=$?
    # Вивід дочірньої команди без ANSI у звіті; вихідний Rustfmt diff теж зберігаємо.
    local cleaned
    cleaned="$(sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' "$LOG_FILE")"
    [[ -z "$cleaned" ]] || emit "$cleaned"
    STEPS+=("$name")
    DURATIONS+=("$(( $(now) - began ))")
    if (( result == 0 )); then
        STATES+=("PASS"); ((pass+=1)); emit "[PASS] $name" 32
    else
        STATES+=("FAIL"); ((fail+=1)); emit "[FAIL] $name (код $result)" 31
    fi
    if [[ "$name" == 'Cargo test' ]]; then
        # Суми лише підсумкових рядків test result, без дублювання проміжних назв тестів.
        while IFS= read -r line; do
            if [[ "$line" =~ ^test\ result:\ (ok|FAILED)\.\ ([0-9]+)\ passed\;\ ([0-9]+)\ failed\;\ ([0-9]+)\ ignored ]]; then
                rust_pass=$((rust_pass + BASH_REMATCH[2]))
                rust_fail=$((rust_fail + BASH_REMATCH[3]))
                rust_ignored=$((rust_ignored + BASH_REMATCH[4]))
            fi
        done < "$LOG_FILE"
    fi
    return "$result"
}

# Перший етап перевіряє форматування без запису у файли.
# Другий запуск Rustfmt має сенс лише після успішного першого:
# при помилці не дублюємо однаковий diff, а явно рахуємо SKIP.
if run_stage 'Cargo fmt' cargo fmt --all -- --check; then
    run_stage 'Cargo fmt check' cargo fmt --all -- --check || true
else
    STEPS+=('Cargo fmt check')
    STATES+=('SKIP')
    DURATIONS+=(0)
    ((skip+=1))
    emit '[SKIP] Cargo fmt check (попередній Cargo fmt завершився помилкою)' 33
fi
run_stage 'Cargo clippy' cargo clippy --all-targets -- -D warnings || true
run_stage 'Cargo test' cargo test || true
run_stage 'TOML documentation' python3 tests/check_toml_documentation.py || true

emit ''
emit '============================================================'
emit " ПІДСУМКОВА СТАТИСТИКА — MikroTik Config Manager v${PROJECT_VERSION}"
emit '============================================================'
printf -v line '%-25s %-8s %s' 'ЕТАП' 'СТАТУС' 'ЧАС'; emit "$line"
for ((i=0; i<${#STEPS[@]}; i++)); do
    printf -v line '%-25s %-8s %s с' "${STEPS[i]}" "${STATES[i]}" "${DURATIONS[i]}"
    case "${STATES[i]}" in PASS) emit "$line" 32;; FAIL) emit "$line" 31;; *) emit "$line" 33;; esac
done
emit '------------------------------------------------------------'
emit "Етапи: PASS $pass | FAIL $fail | SKIP $skip"
emit "Rust-тести: PASS $rust_pass | FAIL $rust_fail | IGNORED $rust_ignored"
emit "Загальний час: $(( $(now) - start )) с"
if ((fail > 0)); then emit 'Фінальний статус: FAIL (код 1)' 31; exit 1; fi
emit 'Фінальний статус: PASS (код 0)' 32
