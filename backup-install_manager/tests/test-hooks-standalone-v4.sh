#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/hooks" "$tmp/src/core" "$tmp/src/hooks"
cp "$repo/src/core/"{path,ui}.sh "$tmp/src/core/"
cp "$repo/src/hooks/hook_runtime.sh" "$tmp/src/hooks/"
cat > "$tmp/hooks/example.sh" <<'HOOK'
#!/usr/bin/env bash
hook_main() {
    printf '%s\n' "${SETUP_ROOT}:$SETUP_DRY_RUN" > "$RESULT_FILE"
}
HOOK
ROOT_DIR="$tmp"
source "$repo/src/core/path.sh"
source "$repo/src/hooks/hooks.sh"
declare -A PACKAGE_HOOKS=([demo]=example)
log() { :; }
export RESULT_FILE="$tmp/result"
DRY_RUN=true
hooks_run demo
[[ ! -e "$RESULT_FILE" ]]
DRY_RUN=false
hooks_run demo
[[ "$(cat "$RESULT_FILE")" == "$tmp:false" ]]
PACKAGE_HOOKS[demo]=not_exists
if hooks_run demo 2>/dev/null; then exit 1; fi
printf '[PASS] test-hooks-standalone-v4\n'
