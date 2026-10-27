#!/usr/bin/env bash
# Інтеграційна перевірка реального MikroTik CHR у VirtualBox.
# Без --upload жодного передавання файлів або зміни RouterOS немає.
# Навіть з --upload: лише SCP, без /import і reset-configuration.
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
vm='MikroTik-CHR'
profile='test'
name=''
upload=false

usage() {
    cat <<'HELP'
Використання: scripts/test-virtualbox-routeros.sh [--vm NAME] [--profile NAME] [--name NAME.rsc] [--upload]

Типовий режим: прочитати стан VirtualBox та RouterOS, згенерувати новий RSC локально.
--upload: додатково передати новий RSC на RouterOS через SCP і підтвердити його у /file.
НЕ виконує /import, reset-configuration, зміну мережі або налаштувань VM.
Вимоги: запущена VM, налаштований SSH key і відомий SSH host key,
заповнений routers/<profile>/.secrets (не додавайте справжні паролі у Git).
HELP
}

while (($#)); do
    case "$1" in
        --vm|--profile|--name)
            option="$1"
            (($# >= 2)) || { echo '[ERROR] Відсутнє значення аргументу' >&2; exit 2; }
            case "$option" in
                --vm) vm="$2" ;;
                --profile) profile="$2" ;;
                --name) name="$2" ;;
            esac
            shift 2 ;;
        --upload) upload=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "[ERROR] Невідомий параметр: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v VBoxManage >/dev/null || { echo '[ERROR] Не знайдено VBoxManage' >&2; exit 1; }
command -v cargo >/dev/null || { echo '[ERROR] Не знайдено cargo' >&2; exit 1; }
[[ "$profile" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo '[ERROR] Некоректний профіль' >&2; exit 2; }
[[ -d "$project_dir/routers/$profile" ]] || { echo "[ERROR] Профіль $profile відсутній" >&2; exit 1; }

# Унікальне ім'я без часових колізій між звичайними запусками.
# Команда build сама відхилить symlink, повторне ім'я та небезпечні символи.
if [[ -z "$name" ]]; then
    name="mcm-vbox-$(date +%Y%m%d-%H%M%S)-${BASHPID}.rsc"
fi
[[ "$name" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*\.rsc$ && "$name" != *..* && "$name" != *.auto.rsc && ${#name} -le 80 ]] || {
    echo '[ERROR] Потрібне безпечне ім’я файлу *.rsc' >&2; exit 2;
}

cd -- "$project_dir"
state="$(VBoxManage showvminfo "$vm" --machinereadable | sed -n 's/^VMState="\([^"]*\)"$/\1/p')"
[[ "$state" == running ]] || { echo "[ERROR] VM '$vm' має стан '$state', очікується running" >&2; exit 1; }
echo "[PASS] VirtualBox VM '$vm' працює"

# Мінімізуємо витік паролів: не друкуємо вміст .secrets і .rsc.
secret_file="routers/$profile/.secrets"
[[ -f "$secret_file" && ! -L "$secret_file" ]] || { echo "[ERROR] $secret_file відсутній або є symlink" >&2; exit 1; }

# Компіляція та read-only підключення до RouterOS — до будь-якого upload.
cargo build --quiet
binary="$project_dir/target/debug/mikrotik-config-manager"
"$binary" verify "$profile" >/dev/null
echo "[PASS] SSH read-only: RouterOS доступний для профілю '$profile'"

# Реальна генерація через CLI: створюється routers/<profile>/build/<name>.
"$binary" build "$profile" --name "$name"
rsc="routers/$profile/build/$name"
[[ -s "$rsc" && -f "$rsc" && ! -L "$rsc" ]] || { echo '[ERROR] RSC не створено або він порожній' >&2; exit 1; }
bytes="$(stat -c %s -- "$rsc")"
mode="$(stat -c %a -- "$rsc")"
[[ "$mode" == 600 ]] || { echo "[ERROR] Небезпечні права RSC: $mode" >&2; exit 1; }
((bytes <= 10 * 1024 * 1024)) || { echo '[ERROR] RSC перевищує 10 MiB' >&2; exit 1; }
# Перевіряємо зміст тільки локально, не виводячи паролі.
grep -q '^# MCM_SECURE_RUNTIME:' "$rsc" || { echo '[ERROR] Не захищений RSC' >&2; exit 1; }
grep -q 'MCM: COMPLETE' "$rsc" || { echo '[ERROR] Відсутній маркер завершення' >&2; exit 1; }
! grep -q '/system reset-configuration' "$rsc" || { echo '[ERROR] RSC містить reset' >&2; exit 1; }
echo "[PASS] Локальний build: $rsc ($bytes bytes; права $mode)"

if [[ "$upload" == true ]]; then
    # Внутрішній upload: перевірка відсутності однойменного файла, SCP -O,
    # після чого /file find і size через read-only SSH.
    "$binary" upload "$profile" --name "$name"
    echo "[PASS] RouterOS підтвердив завантажений '$name'"
else
    echo '[INFO] SCP пропущено. Для справжнього завантаження запусти з --upload.'
fi
echo '[PASS] Інтеграційний сценарій завершено без import/reset'
