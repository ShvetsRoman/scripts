#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/project/hooks" "$tmp/project/src/core" "$tmp/project/src/hooks"
cp "$repo/src/core/"{path,ui}.sh "$tmp/project/src/core/"
cp "$repo/src/hooks/hook_runtime.sh" "$tmp/project/src/hooks/"
cat > "$tmp/project/hooks/fail.sh" <<'HOOK'
#!/usr/bin/env bash
hook_main() { return 17; }
HOOK
cat > "$tmp/project/hooks/next.sh" <<'HOOK'
#!/usr/bin/env bash
hook_main() { printf '%s\n' executed > "${RESULT_FILE:?}"; }
HOOK
cat > "$tmp/project/hooks/bad.sh" <<'HOOK'
#!/usr/bin/env bash
if then
HOOK
ROOT_DIR="$tmp/project"
source "$repo/src/core/path.sh"
source "$repo/src/hooks/hooks.sh"
log() { :; }
declare -A PACKAGE_HOOKS=([demo]='fail next')
export RESULT_FILE="$tmp/result"
DRY_RUN=false
rc=0
hooks_run demo || rc=$?
[[ "$rc" -eq 17 && ! -e "$RESULT_FILE" ]]
PACKAGE_HOOKS[demo]='next'
hooks_run demo
[[ "$(cat "$RESULT_FILE")" == executed ]]
rm -f -- "$RESULT_FILE"
DRY_RUN=true
PACKAGE_HOOKS[demo]='fail next'
hooks_run demo
[[ ! -e "$RESULT_FILE" ]]
DRY_RUN=false
PACKAGE_HOOKS[demo]='bad'
if hooks_run demo 2>/dev/null; then exit 1; fi
PACKAGE_HOOKS[demo]='next'
ln -s "$tmp/project/hooks/next.sh" "$tmp/project/hooks/linked.sh"
PACKAGE_HOOKS[demo]='linked'
if hooks_run demo 2>/dev/null; then exit 1; fi
mv "$tmp/project/hooks" "$tmp/project/real_hooks"
ln -s "$tmp/project/real_hooks" "$tmp/project/hooks"
PACKAGE_HOOKS[demo]='next'
if hooks_run demo 2>/dev/null; then exit 1; fi
printf '[PASS] test-hooks-failure-v142\n'
