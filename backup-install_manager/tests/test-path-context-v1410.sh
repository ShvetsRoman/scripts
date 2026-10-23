#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/project"
mkdir -p "$ROOT_DIR/hooks" "$tmp/logs"
# shellcheck source=/dev/null
source "$repo/src/core/path.sh"
# shellcheck source=/dev/null
source "$repo/src/hooks/hooks.sh"
log() { :; }
cat > "$ROOT_DIR/hooks/probe.sh" <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
hook_main() {
    [[ "$SETUP_ROOT" == "$EXPECTED_ROOT" ]]
    [[ "$SETUP_LOG_FILE" == "$EXPECTED_LOG" ]]
    [[ "$SETUP_RUN_ID" == audit-123 ]]
    [[ "$SETUP_COLOR" == never ]]
    [[ "$SETUP_TEST_MODE" == true ]]
    [[ "$SETUP_NO_CLEAR" == true ]]
    [[ "$SETUP_DRY_RUN" == false ]]
    [[ "$(path_hooks_root)" == "$ROOT_DIR/hooks" ]]
    printf 'ok\n' > "$RESULT_FILE"
}
HOOK
# Hook ізольований: завантажує той самий модуль шляхів зі свого проєкту.
mkdir -p "$ROOT_DIR/src/core" "$ROOT_DIR/src/hooks"
cp "$repo/src/core/"{path,ui}.sh "$ROOT_DIR/src/core/"
cp "$repo/src/hooks/hook_runtime.sh" "$ROOT_DIR/src/hooks/"
export EXPECTED_ROOT="$ROOT_DIR" EXPECTED_LOG="$tmp/logs/test.log" RESULT_FILE="$tmp/result"
export SETUP_LOG_FILE="$EXPECTED_LOG"
export SETUP_RUN_ID=audit-123
export SETUP_COLOR=never
export SETUP_TEST_MODE=true
export SETUP_NO_CLEAR=true
DRY_RUN=false
# Перевіряємо звичайний hook.
# Масив читає hooks_run із src/hooks/hooks.sh.
# shellcheck disable=SC2034
declare -A PACKAGE_HOOKS=([demo]=probe)
hooks_run demo
[[ "$(cat "$RESULT_FILE")" == ok ]]
rm -f -- "$RESULT_FILE"
# І той самий контракт для прив'язаного hook.
hooks_run_bound probe demo-package
[[ "$(cat "$RESULT_FILE")" == ok ]]
rm -f -- "$RESULT_FILE"
# Dry-run не запускає дочірній процес.
# Значення читається hooks_run із src/hooks/hooks.sh.
# shellcheck disable=SC2034
DRY_RUN=true
hooks_run demo
hooks_run_bound probe demo-package
[[ ! -e "$RESULT_FILE" ]]
printf '[PASS] test-path-context-v1410\n'
