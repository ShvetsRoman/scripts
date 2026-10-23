#!/usr/bin/env bash
# Перевірка ізольованого пропуску проблемного пакета.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export TEST_MARKER="$tmp/install"
cat > "$tmp/pacman" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    -Qq) exit 0 ;;
    -Si) for arg in "$@"; do [[ "$arg" == missing ]] && exit 1; done; exit 0 ;;
    -S) printf 'installed:%s\n' "${*: -1}" >> "$TEST_MARKER"; exit "${TEST_INSTALL_EXIT:-0}" ;;
    *) exit 2 ;;
esac
MOCK
cat > "$tmp/sudo" <<'MOCK'
#!/usr/bin/env bash
"$@"
MOCK
chmod +x "$tmp/pacman" "$tmp/sudo"
export PATH="$tmp:$PATH"
log() { :; }
stage() { :; }
header() { :; }
registry_valid() { [[ "$1" == demo ]]; }
registry_title() { printf 'Демо'; }
packages_select() {
    PACMAN_PACKAGES=(alpha missing beta)
    AUR_PACKAGES=()
    CONFIG_ITEMS=(example)
}
hooks_validate() { return 0; }
hooks_run_bound() { printf 'bound:%s:%s\n' "$1" "$2" >> "$TEST_MARKER"; }
configs_apply() { printf 'configs\n' >> "$TEST_MARKER"; }
hooks_run() { printf 'general\n' >> "$TEST_MARKER"; }
declare -A PACKAGE_HOOKS=([demo]='somehook') PACKAGE_BOUND_HOOKS=([demo\|missing]=bound_missing [demo\|alpha]=bound_alpha)
DRY_RUN=false
CONFIGS_ONLY=false
NO_CONFIGS=false
pkg_run_module demo >/dev/null
expected=$'installed:alpha\ninstalled:beta\nconfigs\ngeneral\nbound:bound_alpha:alpha'
[[ "$(cat "$TEST_MARKER")" == "$expected" ]]
: > "$TEST_MARKER"
# Помилка встановлення конкретного пакета не зупиняє наступні пакети.
export TEST_INSTALL_EXIT=29
pkg_run_module demo >/dev/null
[[ "$(cat "$TEST_MARKER")" == $'installed:alpha\ninstalled:beta\nconfigs\ngeneral' ]]
printf '[PASS] test-packages-failure-v144\n'
