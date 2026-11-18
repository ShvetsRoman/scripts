#!/usr/bin/env bash
# ============================================================
# Virtualization Manager 1.0.0
# Керування VirtualBox та KVM/QEMU на Arch Linux
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_NAME='Virtualization Manager'
readonly APP_VERSION='1.0.0'
readonly VBOX_MACHINE_FOLDER="$HOME/.virtualbox"
readonly VBOX_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/VirtualBox"
readonly LIBVIRT_USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/libvirt"
readonly LIBVIRT_USER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/libvirt"
readonly LIBVIRT_USER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/virt-manager"
readonly KVM_IMAGE_DIR='/var/lib/libvirt/images'
readonly KVM_BOOT_DIR='/var/lib/libvirt/boot'
readonly LIBVIRT_SYSTEM_CONFIG='/etc/libvirt'
readonly LIBVIRT_SYSTEM_DATA='/var/lib/libvirt'

if [[ -t 1 ]]; then
    readonly C_RED=$'\033[0;31m' C_GREEN=$'\033[0;32m' C_YELLOW=$'\033[0;33m'
    readonly C_BLUE=$'\033[0;34m' C_CYAN=$'\033[0;36m' C_RESET=$'\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_RESET=''
fi

log_info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_ok() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_error() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_section() { printf '\n%s== %s ==%s\n' "$C_CYAN" "$*" "$C_RESET"; }

on_error() {
    local code=$?
    log_error "Помилка в рядку ${BASH_LINENO[0]:-невідомо}; код завершення: $code"
    exit "$code"
}
trap on_error ERR

usage() {
    cat <<USAGE
$APP_NAME $APP_VERSION

Керування VirtualBox та KVM/QEMU на Arch Linux.

Використання:
  ./$(basename "$0")                         Показати цю інструкцію
  ./$(basename "$0") --help                  Показати цю інструкцію
  ./$(basename "$0") --version               Показати версію

Встановлення:
  ./$(basename "$0") --install virtualbox    Встановити VirtualBox + DKMS + Headers
  ./$(basename "$0") --install kvm           Встановити KVM/QEMU + libvirt + Virt-Manager
  ./$(basename "$0") --install both          Встановити обидва гіпервізори

Звичайне видалення (усі дані VM зберігаються):
  ./$(basename "$0") --remove virtualbox
  ./$(basename "$0") --remove kvm
  ./$(basename "$0") --remove both

Повне видалення (пакети та дані стандартних сховищ):
  ./$(basename "$0") --remove virtualbox --purge
  ./$(basename "$0") --remove kvm --purge
  ./$(basename "$0") --remove both --purge

Діагностика без внесення змін:
  ./$(basename "$0") --check

Поведінка:
  • Без аргументів скрипт лише показує цю інструкцію — меню немає.
  • --remove без --purge видаляє програми, але зберігає VM, диски,
    ISO, snapshots, сховища та конфігурації користувача.
  • --purge вимагає явного підтвердження словом DELETE.
  • Повне очищення обмежене відомими стандартними шляхами; зовнішні
    сховища та ISO поза ними не видаляються автоматично.
  • Скрипт запускається від звичайного користувача та сам викликає sudo.

Приклади:
  ./$(basename "$0") --check
  ./$(basename "$0") --install kvm
  ./$(basename "$0") --remove virtualbox
  ./$(basename "$0") --remove virtualbox --purge
USAGE
}

require_arch() {
    [[ -f /etc/arch-release ]] || {
        log_error 'Підтримується лише Arch Linux.'
        exit 1
    }
    [[ $EUID -ne 0 ]] || {
        log_error 'Запускай скрипт від звичайного користувача, не через sudo.'
        exit 1
    }
    command -v pacman >/dev/null || {
        log_error 'Не знайдено pacman.'
        exit 1
    }
    command -v sudo >/dev/null || {
        log_error 'Не знайдено sudo.'
        exit 1
    }
    command -v systemctl >/dev/null || {
        log_error 'Не знайдено systemctl.'
        exit 1
    }
    sudo -v
}

confirm() {
    local prompt=$1 answer
    printf '%s [y/N]: ' "$prompt"
    read -r answer
    [[ $answer =~ ^[Yy]$ ]]
}

confirm_word() {
    local prompt=$1 expected=$2 answer
    printf '%s\n' "$prompt"
    printf 'Для підтвердження введи %s: ' "$expected"
    read -r answer
    [[ $answer == "$expected" ]]
}

pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

install_pkg_list() {
    local -a wanted=() missing=()
    local p
    wanted=("$@")
    for p in "${wanted[@]}"; do
        pkg_installed "$p" || missing+=("$p")
    done
    if ((${#missing[@]} == 0)); then
        log_ok 'Усі цільові пакети вже встановлені.'
        return 0
    fi
    log_info "Пакети для встановлення: ${missing[*]}"
    sudo pacman -Syu --needed "${missing[@]}"
}

remove_pkg_list() {
    local -a installed=()
    local p
    for p in "$@"; do
        pkg_installed "$p" && installed+=("$p")
    done
    if ((${#installed[@]} == 0)); then
        log_info 'Цільові пакети не встановлені.'
        return 0
    fi
    log_info "Пакети для видалення: ${installed[*]}"
    # -R без -s/-n: не прибираємо автоматично спільні залежності та конфігурації.
    sudo pacman -R -- "${installed[@]}"
}

# Повертає заголовки лише для офіційних ядер, які реально встановлені.
get_installed_kernel_headers() {
    local kernel header
    local -a kernels=(linux linux-lts linux-zen linux-hardened)
    for kernel in "${kernels[@]}"; do
        if pkg_installed "$kernel"; then
            header="${kernel}-headers"
            if pacman -Si "$header" >/dev/null 2>&1; then
                printf '%s\n' "$header"
            else
                log_warn "Для $kernel не знайдено пакет $header у налаштованих репозиторіях." >&2
            fi
        fi
    done
}

check_kernel_headers() {
    log_section 'Ядра та Headers'
    printf 'Активне ядро: %s\n' "$(uname -r)"
    printf 'Встановлені ядра:\n'
    pacman -Qq | grep -E '^(linux|linux-lts|linux-zen|linux-hardened)$' || true
    printf 'Встановлені kernel headers:\n'
    pacman -Qq | grep -E '^linux(-lts|-zen|-hardened)?-headers$' || true
    if [[ -e "/usr/lib/modules/$(uname -r)/build" ]]; then
        log_ok 'Headers активного ядра доступні.'
    else
        log_warn 'Не знайдено build-посилання для активного ядра.'
    fi
}

check_cpu_virtualization() {
    log_section 'Апаратна віртуалізація'
    local vendor flags
    vendor=$(lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    flags=$(awk -F: '/^flags[ \t]*:/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
    printf 'CPU vendor: %s\n' "${vendor:-невідомо}"
    if [[ " $flags " == *' vmx '* ]]; then
        log_ok 'Intel VT-x (vmx) підтримується CPU.'
    elif [[ " $flags " == *' svm '* ]]; then
        log_ok 'AMD-V (svm) підтримується CPU.'
    else
        log_warn 'Прапорці vmx/svm не знайдені в /proc/cpuinfo.'
    fi
    [[ -e /dev/kvm ]] && log_ok '/dev/kvm існує.' || log_warn '/dev/kvm відсутній.'
    lsmod | grep -E '^(kvm|kvm_intel|kvm_amd)\b' || log_warn 'Модулі KVM не завантажені.'
}

vbox_installed() { pkg_installed virtualbox || pkg_installed virtualbox-host-dkms; }
kvm_installed() { pkg_installed libvirt || pkg_installed qemu-full || pkg_installed virt-manager; }

install_virtualbox() {
    log_section 'Встановлення VirtualBox'
    local -a packages=(virtualbox virtualbox-host-dkms dkms virtualbox-guest-iso)
    local -a headers=()
    mapfile -t headers < <(get_installed_kernel_headers)
    if ((${#headers[@]} == 0)); then
        log_error 'Не знайдено відповідних пакетів headers для встановлених офіційних ядер.'
        log_info 'Перевір ядро та встанови відповідний пакет *-headers перед продовженням.'
        return 1
    fi
    packages+=("${headers[@]}")
    printf 'Ядро зараз: %s\n' "$(uname -r)"
    printf 'Headers, які будуть забезпечені: %s\n' "${headers[*]}"
    log_info 'Буде встановлено VirtualBox, DKMS, Guest ISO та headers усіх виявлених офіційних ядер.'
    confirm 'Продовжити встановлення VirtualBox?' || {
        log_warn 'Скасовано.'
        return 0
    }
    install_pkg_list "${packages[@]}"
    mkdir -p "$VBOX_MACHINE_FOLDER"
    if command -v VBoxManage >/dev/null 2>&1; then
        VBoxManage setproperty machinefolder "$VBOX_MACHINE_FOLDER"
        log_ok "Стандартне сховище VirtualBox: $VBOX_MACHINE_FOLDER"
    else
        log_warn 'VBoxManage ще недоступний; шлях сховища потрібно встановити після завершення встановлення.'
    fi
    if getent group vboxusers >/dev/null 2>&1; then
        sudo usermod -aG vboxusers "$USER"
        log_ok "Користувача $USER додано до vboxusers (потрібен повторний вхід)."
    fi
    if ! sudo modprobe vboxdrv; then
        log_warn 'Не вдалося завантажити vboxdrv. Перевір dkms status та журнал ядра.'
    fi
    log_ok 'Встановлення VirtualBox завершено.'
}

install_kvm() {
    log_section 'Встановлення KVM/QEMU'
    check_cpu_virtualization
    if [[ ! -e /dev/kvm ]]; then
        log_warn 'До встановлення не виявлено /dev/kvm. Переконайся, що VT-x/AMD-V увімкнено в UEFI.'
    fi
    # virt-install є окремим split-пакетом у репозиторіях Arch; qemu-full дає повний набір QEMU.
    local -a packages=(
        qemu-full libvirt virt-manager virt-install virt-viewer
        edk2-ovmf swtpm dnsmasq iptables-nft ebtables vde2
        openbsd-netcat spice-gtk guestfs-tools libosinfo
    )
    log_info 'Буде встановлено повний набір QEMU, libvirt, GUI/CLI, UEFI, TPM, мережеві та гостьові інструменти.'
    confirm 'Продовжити встановлення KVM/QEMU?' || {
        log_warn 'Скасовано.'
        return 0
    }
    install_pkg_list "${packages[@]}"

    if getent group libvirt >/dev/null 2>&1; then
        sudo usermod -aG libvirt "$USER"
        log_ok "Користувача $USER додано до libvirt (потрібен повторний вхід)."
    fi
    if getent group kvm >/dev/null 2>&1; then
        sudo usermod -aG kvm "$USER"
    fi

    # Використовуємо модульні libvirt daemons; не запускаємо одночасно legacy libvirtd.
    local unit
    local -a units=(virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket)
    for unit in "${units[@]}"; do
        if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
            sudo systemctl enable --now "$unit"
            log_ok "Увімкнено $unit"
        else
            log_warn "Systemd unit $unit не знайдено; пропускаю."
        fi
    done

    if command -v virsh >/dev/null 2>&1; then
        if sudo virsh -c qemu:///system net-info default >/dev/null 2>&1; then
            sudo virsh -c qemu:///system net-autostart default || true
            sudo virsh -c qemu:///system net-start default 2>/dev/null || true
            log_ok 'Мережа libvirt default перевірена та налаштована на автозапуск.'
        elif [[ -r /usr/share/libvirt/networks/default.xml ]]; then
            sudo virsh -c qemu:///system net-define /usr/share/libvirt/networks/default.xml
            sudo virsh -c qemu:///system net-autostart default
            sudo virsh -c qemu:///system net-start default
            log_ok 'Створено стандартну NAT-мережу libvirt default.'
        else
            log_warn 'Не знайдено default network XML. Мережу можна створити через virt-manager або virsh.'
        fi
    fi
    log_ok 'Встановлення KVM/QEMU завершено.'
    log_warn 'Для застосування груп користувача вийди із сеансу та увійди знову.'
}

# Виявляє активні VM, щоб не видаляти файли під час їх використання.
assert_no_running_vms() {
    local target=$1
    if [[ $target == virtualbox || $target == both ]]; then
        if command -v VBoxManage >/dev/null 2>&1; then
            local running
            running=$(VBoxManage list runningvms 2>/dev/null || true)
            if [[ -n $running ]]; then
                log_error 'VirtualBox має запущені VM. Заверши їх вручну перед видаленням:'
                printf '%s\n' "$running"
                return 1
            fi
        fi
    fi
    if [[ $target == kvm || $target == both ]]; then
        if command -v virsh >/dev/null 2>&1; then
            local running
            running=$(sudo virsh -c qemu:///system list --state-running --name 2>/dev/null | sed '/^$/d' || true)
            if [[ -n $running ]]; then
                log_error 'KVM має запущені VM. Заверши їх вручну перед видаленням:'
                printf '%s\n' "$running"
                return 1
            fi
        fi
    fi
}

remove_virtualbox_standard() {
    log_section 'Звичайне видалення VirtualBox'
    log_info 'Буде видалено пакети VirtualBox та DKMS-модуль.'
    log_ok "Буде збережено $VBOX_MACHINE_FOLDER та $VBOX_CONFIG_DIR."
    confirm 'Видалити VirtualBox без видалення даних?' || {
        log_warn 'Скасовано.'
        return 0
    }
    sudo modprobe -r vboxnetadp vboxnetflt vboxdrv 2>/dev/null || true
    remove_pkg_list virtualbox virtualbox-host-dkms
    log_warn 'dkms, headers та virtualbox-guest-iso не видалялися автоматично: вони можуть бути потрібні іншим ядрам/системним задачам.'
    log_ok 'Звичайне видалення VirtualBox завершено.'
}

remove_kvm_standard() {
    log_section 'Звичайне видалення KVM/QEMU'
    log_ok 'VM, диски, ISO, сховища та конфігурації libvirt залишаться на місці.'
    confirm 'Видалити пакети KVM/QEMU без видалення даних?' || {
        log_warn 'Скасовано.'
        return 0
    }
    local unit
    for unit in virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket; do
        if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
            sudo systemctl disable --now "$unit" 2>/dev/null || true
        fi
    done
    remove_pkg_list qemu-full libvirt virt-manager virt-install virt-viewer edk2-ovmf swtpm dnsmasq iptables-nft ebtables vde2 openbsd-netcat spice-gtk guestfs-tools libosinfo
    log_warn 'Не видалялись групи libvirt/kvm, конфігурації, storage pools та каталоги VM.'
    log_ok 'Звичайне видалення KVM/QEMU завершено.'
}

# Безпечна перевірка шляху: не дозволяємо /, HOME або системний корінь як ціль.
safe_remove_tree() {
    local path=$1 canonical allowed
    [[ -e $path || -L $path ]] || {
        log_info "Немає: $path"
        return 0
    }
    canonical=$(realpath -m -- "$path")
    [[ $canonical != / && $canonical != "$HOME" && $canonical != /home ]] || {
        log_error "Заборонено видаляти небезпечний шлях: $canonical"
        return 1
    }
    allowed=0
    case "$canonical" in
        "$VBOX_MACHINE_FOLDER" | "$VBOX_CONFIG_DIR" | "$LIBVIRT_USER_DATA" | "$LIBVIRT_USER_CACHE" | "$LIBVIRT_USER_CONFIG" | "$KVM_IMAGE_DIR" | "$KVM_BOOT_DIR" | "$LIBVIRT_SYSTEM_DATA" | "$LIBVIRT_SYSTEM_CONFIG")
            allowed=1
            ;;
    esac
    ((allowed == 1)) || {
        log_error "Шлях поза allowlist, автоматичне видалення заборонено: $canonical"
        return 1
    }
    log_warn "Буде остаточно видалено: $canonical"
    sudo rm -rf --one-file-system -- "$canonical"
}

purge_virtualbox_data() {
    log_section 'Повне видалення даних VirtualBox'
    local machine_folder=$VBOX_MACHINE_FOLDER
    if command -v VBoxManage >/dev/null 2>&1; then
        local actual
        actual=$(VBoxManage getproperty machinefolder 2>/dev/null | sed -n 's/^Value: //p' | head -n1 || true)
        if [[ -n $actual ]]; then
            machine_folder=$actual
        fi
    fi
    printf 'Machine folder VirtualBox: %s\n' "$machine_folder"
    printf 'Глобальна конфігурація: %s\n' "$VBOX_CONFIG_DIR"
    log_warn 'ISO/диски поза machine folder не видаляються автоматично: це можуть бути спільні або особисті файли.'
    log_info 'План видалення VirtualBox:'
    printf '  - Machine folder: %s\n' "$machine_folder"
    printf '  - Global config:  %s\n' "$VBOX_CONFIG_DIR"
    if [[ $machine_folder != "$VBOX_MACHINE_FOLDER" ]]; then
        log_warn 'Machine folder відрізняється від стандартного ~/.virtualbox.'
        log_warn 'Автоматичне видалення нестандартного шляху заборонене; прибери його вручну після перевірки.'
    else
        safe_remove_tree "$machine_folder"
    fi
    safe_remove_tree "$VBOX_CONFIG_DIR"
}

purge_kvm_data() {
    log_section 'Повне видалення даних KVM/libvirt'
    log_warn 'Буде видалено стандартні системні каталоги libvirt, включно з XML VM, мережами та стандартними образами.'
    log_warn 'Користувацькі та зовнішні storage pools поза стандартними каталогами не видаляються автоматично.'
    log_info 'План видалення KVM/libvirt:'
    printf '  - %s\n' "$LIBVIRT_USER_CONFIG" "$LIBVIRT_USER_DATA" "$LIBVIRT_USER_CACHE" \
        "$KVM_IMAGE_DIR" "$KVM_BOOT_DIR" "$LIBVIRT_SYSTEM_CONFIG" "$LIBVIRT_SYSTEM_DATA (лише якщо після очищення стандартних каталогів порожній)"
    if command -v virsh >/dev/null 2>&1; then
        log_info 'Відомі storage pools:'
        sudo virsh -c qemu:///system pool-list --all 2>/dev/null || true
        log_info 'Відомі віртуальні мережі:'
        sudo virsh -c qemu:///system net-list --all 2>/dev/null || true
    fi
    safe_remove_tree "$LIBVIRT_USER_CONFIG"
    safe_remove_tree "$LIBVIRT_USER_DATA"
    safe_remove_tree "$LIBVIRT_USER_CACHE"
    safe_remove_tree "$KVM_IMAGE_DIR"
    safe_remove_tree "$KVM_BOOT_DIR"
    safe_remove_tree "$LIBVIRT_SYSTEM_CONFIG"
    # /var/lib/libvirt може містити дані сторонніх/custom storage pools.
    # Його повне видалення виконується лише якщо після видалення стандартних
    # каталогів він порожній; інакше залишаємо невідомі дані недоторканими.
    if [[ -d $LIBVIRT_SYSTEM_DATA ]]; then
        if [[ -z $(sudo find "$LIBVIRT_SYSTEM_DATA" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
            safe_remove_tree "$LIBVIRT_SYSTEM_DATA"
        else
            log_warn "У $LIBVIRT_SYSTEM_DATA залишилися невідомі/custom дані; каталог збережено. Перевір його вручну."
        fi
    fi
}

show_purge_plan() {
    local target=$1 machine_folder=$VBOX_MACHINE_FOLDER
    log_section 'Попередній план повного видалення'
    if [[ $target == virtualbox || $target == both ]]; then
        if command -v VBoxManage >/dev/null 2>&1; then
            local actual
            actual=$(VBoxManage getproperty machinefolder 2>/dev/null | sed -n 's/^Value: //p' | head -n1 || true)
            [[ -n $actual ]] && machine_folder=$actual
        fi
        printf 'VirtualBox:\n  - Machine folder: %s\n  - Global config:  %s\n' "$machine_folder" "$VBOX_CONFIG_DIR"
        log_warn 'Зовнішні ISO/диски поза machine folder не видалятимуться автоматично.'
        if [[ $machine_folder != "$VBOX_MACHINE_FOLDER" ]]; then
            log_warn 'Machine folder відрізняється від ~/.virtualbox і буде пропущений автоматичним очищенням.'
        fi
    fi
    if [[ $target == kvm || $target == both ]]; then
        printf 'KVM/libvirt:\n'
        printf '  - %s\n' "$LIBVIRT_USER_CONFIG" "$LIBVIRT_USER_DATA" "$LIBVIRT_USER_CACHE" \
            "$KVM_IMAGE_DIR" "$KVM_BOOT_DIR" "$LIBVIRT_SYSTEM_CONFIG" "$LIBVIRT_SYSTEM_DATA (лише якщо порожній)"
        log_warn 'Custom storage pools поза стандартними каталогами залишаться недоторканими.'
        if command -v virsh >/dev/null 2>&1; then
            printf '\nПоточні storage pools:\n'
            sudo virsh -c qemu:///system pool-list --all 2>/dev/null || true
            printf '\nПоточні libvirt networks:\n'
            sudo virsh -c qemu:///system net-list --all 2>/dev/null || true
        fi
    fi
}

remove_target() {
    local target=$1 purge=${2:-false}
    [[ $target == virtualbox || $target == kvm || $target == both ]] || {
        log_error 'Невідомий гіпервізор.'
        return 2
    }
    assert_no_running_vms "$target"
    if [[ $purge == true ]]; then
        log_section 'РЕЖИМ ПОВНОГО ВИДАЛЕННЯ'
        log_warn 'Ця операція може безповоротно видалити VM, диски, snapshots, ISO у стандартних сховищах та мережеві налаштування.'
        printf 'Ціль: %s\n' "$target"
        show_purge_plan "$target"
        confirm_word 'Переглянь перелік шляхів вище та підтверди повне видалення.' 'DELETE' || {
            log_warn 'Підтвердження не збіглося. Нічого не видалено.'
            return 0
        }
        if [[ $target == virtualbox || $target == both ]]; then
            purge_virtualbox_data
            sudo modprobe -r vboxnetadp vboxnetflt vboxdrv 2>/dev/null || true
            remove_pkg_list virtualbox virtualbox-host-dkms
        fi
        if [[ $target == kvm || $target == both ]]; then
            local unit
            for unit in virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket virtqemud.service virtnetworkd.service virtstoraged.service virtlogd.service; do
                if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "$unit"; then
                    sudo systemctl disable --now "$unit" 2>/dev/null || true
                fi
            done
            purge_kvm_data
            remove_pkg_list qemu-full libvirt virt-manager virt-install virt-viewer edk2-ovmf swtpm dnsmasq iptables-nft ebtables bridge-utils vde2 openbsd-netcat spice-gtk guestfs-tools libosinfo
        fi
        log_ok 'Сценарій повного видалення завершено. Перевір попередження про нестандартні сховища.'
    else
        if [[ $target == virtualbox || $target == both ]]; then remove_virtualbox_standard; fi
        if [[ $target == kvm || $target == both ]]; then remove_kvm_standard; fi
    fi
}

show_status() {
    log_section 'Загальна діагностика'
    check_kernel_headers
    check_cpu_virtualization
    log_section 'VirtualBox'
    if vbox_installed; then log_ok 'Пакети VirtualBox виявлені.'; else log_warn 'VirtualBox не встановлений.'; fi
    if command -v VBoxManage >/dev/null 2>&1; then
        VBoxManage --version || true
        printf 'Machine folder: '
        VBoxManage getproperty machinefolder 2>/dev/null | sed -n 's/^Value: / /p' || true
        lsmod | grep -E '^vbox(drv|netflt|netadp)\b' || log_warn 'Модулі VirtualBox не завантажені.'
        dkms status 2>/dev/null | grep -i vbox || log_warn 'Запис VirtualBox не знайдений у DKMS.'
    else
        log_warn 'VBoxManage недоступний.'
    fi
    log_section 'KVM/QEMU'
    if kvm_installed; then log_ok 'Пакети KVM/libvirt виявлені.'; else log_warn 'KVM/libvirt не встановлений.'; fi
    command -v qemu-system-x86_64 >/dev/null 2>&1 && qemu-system-x86_64 --version | head -n1 || log_warn 'QEMU system emulator не знайдений.'
    command -v virt-manager >/dev/null 2>&1 && log_ok 'Virt-Manager доступний.' || log_warn 'Virt-Manager недоступний.'
    if command -v virsh >/dev/null 2>&1; then
        sudo virsh -c qemu:///system list --all 2>&1 || true
        sudo virsh -c qemu:///system net-list --all 2>&1 || true
    fi
    for unit in virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket; do
        systemctl is-active --quiet "$unit" && log_ok "$unit active" || log_warn "$unit не active"
    done
}

main() {
    local action='' target='' purge=false

    # Без аргументів нічого не змінюємо: показуємо довідку.
    if (($# == 0)); then
        usage
        return 0
    fi

    while (($#)); do
        case $1 in
            --check)
                [[ -z $action ]] || {
                    log_error 'Вкажи лише одну основну дію.'
                    exit 2
                }
                action=check
                shift
                ;;
            --install)
                [[ -z $action ]] || {
                    log_error 'Вкажи лише одну основну дію.'
                    exit 2
                }
                (($# >= 2)) || {
                    log_error 'Після --install потрібно вказати virtualbox, kvm або both.'
                    usage
                    exit 2
                }
                action=install
                target=$2
                shift 2
                ;;
            --remove)
                [[ -z $action ]] || {
                    log_error 'Вкажи лише одну основну дію.'
                    exit 2
                }
                (($# >= 2)) || {
                    log_error 'Після --remove потрібно вказати virtualbox, kvm або both.'
                    usage
                    exit 2
                }
                action=remove
                target=$2
                shift 2
                ;;
            --purge)
                [[ $purge == false ]] || {
                    log_error '--purge вказано повторно.'
                    exit 2
                }
                purge=true
                shift
                ;;
            --version)
                printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
                return 0
                ;;
            -h | --help)
                usage
                return 0
                ;;
            *)
                log_error "Невідомий аргумент: $1"
                usage
                exit 2
                ;;
        esac
    done

    if [[ $purge == true && $action != remove ]]; then
        log_error '--purge можна використовувати лише разом із --remove.'
        exit 2
    fi

    if [[ $action == check ]]; then
        require_arch
        show_status
        return 0
    fi

    require_arch

    case $action in
        install)
            case $target in
                virtualbox) install_virtualbox ;;
                kvm) install_kvm ;;
                both)
                    install_virtualbox
                    install_kvm
                    ;;
                *)
                    log_error 'Для --install вкажи virtualbox, kvm або both.'
                    usage
                    exit 2
                    ;;
            esac
            ;;
        remove)
            case $target in
                virtualbox | kvm | both) remove_target "$target" "$purge" ;;
                *)
                    log_error 'Для --remove вкажи virtualbox, kvm або both.'
                    usage
                    exit 2
                    ;;
            esac
            ;;
        *)
            log_error 'Не вказано дію.'
            usage
            exit 2
            ;;
    esac
}

main "$@"
