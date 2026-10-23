#!/usr/bin/env bash
# Єдина точка входу, ізоляція, логування та коди завершення.
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/hooks" "$tmp/src/core" "$tmp/src/hooks"
cp "$repo/src/core/"{path,ui}.sh "$tmp/src/core/"
cp "$repo/src/hooks/hook_runtime.sh" "$tmp/src/hooks/"
cat > "$tmp/hooks/probe.sh" <<'HOOK'
hook_main() {
    [[ "$ROOT_DIR" == "$SETUP_ROOT" ]]
    [[ "$DRY_RUN" == false ]]
    [[ "$(path_hooks_root)" == "$ROOT_DIR/hooks" ]]
    log info 'Контрольний hook'
    printf '%s\n' "$BASHPID" > "$RESULT_FILE"
    return 0
}
HOOK
cat > "$tmp/hooks/fail.sh" <<'HOOK'
hook_main() { return 17; }
HOOK
cat > "$tmp/hooks/missing.sh" <<'HOOK'
other() { :; }
HOOK
ROOT_DIR="$tmp"
source "$repo/src/core/path.sh"
source "$repo/src/hooks/hooks.sh"
log() { :; }
export RESULT_FILE="$tmp/result" SETUP_LOG_FILE="$tmp/audit.log" SETUP_RUN_ID='runtime-test'
DRY_RUN=false
# shellcheck disable=SC2034
 declare -A PACKAGE_HOOKS=([demo]=probe)
hooks_run demo
[[ -s "$RESULT_FILE" ]]
grep -Fq 'Контрольний hook' "$SETUP_LOG_FILE"
[[ "$(cat "$RESULT_FILE")" != "$BASHPID" ]]
rm "$RESULT_FILE"
DRY_RUN=true
hooks_run demo
[[ ! -e "$RESULT_FILE" ]]
DRY_RUN=false
PACKAGE_HOOKS[demo]=fail
rc=0
hooks_run demo >/dev/null 2>&1 || rc=$?
[[ "$rc" == 17 ]]
PACKAGE_HOOKS[demo]=missing
rc=0
hooks_run demo >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]]
printf '[PASS] test-hook-runtime-v1422\n'
