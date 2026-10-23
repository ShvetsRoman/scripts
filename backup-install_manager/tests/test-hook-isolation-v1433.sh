#!/usr/bin/env bash
# Перевірка межі окремого процесу і помилок завантаження hook.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/src/core" "$tmp/src/hooks" "$tmp/hooks"
cp "$root/src/core/path.sh" "$root/src/core/ui.sh" "$tmp/src/core/"
cp "$root/src/hooks/hook_runtime.sh" "$tmp/src/hooks/"
cat > "$tmp/hooks/probe.sh" <<'HOOK'
hook_main() {
    [[ "$ROOT_DIR" == "$SETUP_ROOT" ]]
    [[ "$DRY_RUN" == true ]]
    [[ "$SETUP_RUN_ID" == audit-v1433 ]]
    printf '%s\n' "${BASHPID}" > "$PROBE_PID_FILE"
}
HOOK
export PROBE_PID_FILE="$tmp/pid" SETUP_RUN_ID=audit-v1433 SETUP_DRY_RUN=true SETUP_LOG_FILE="$tmp/log"
SETUP_ROOT="$tmp" bash "$tmp/src/hooks/hook_runtime.sh" "$tmp/hooks/probe.sh"
[[ -s "$tmp/pid" ]]
[[ "$(cat "$tmp/pid")" != "$BASHPID" ]]
# Відсутній обов'язковий контекст: відмова без запуску hook.
rc=0
env -u SETUP_ROOT bash "$tmp/src/hooks/hook_runtime.sh" "$tmp/hooks/probe.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 ]]
# Некоректний файл hook: код 2.
rc=0
SETUP_ROOT="$tmp" bash "$tmp/src/hooks/hook_runtime.sh" "$tmp/hooks/absent.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]]
# Hook без hook_main(): код 2.
printf 'unused() { :; }\n' > "$tmp/hooks/missing.sh"
rc=0
SETUP_ROOT="$tmp" bash "$tmp/src/hooks/hook_runtime.sh" "$tmp/hooks/missing.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]]
# Помилка hook_main() зберігає код завершення.
printf 'hook_main() { return 23; }\n' > "$tmp/hooks/fail.sh"
rc=0
SETUP_ROOT="$tmp" bash "$tmp/src/hooks/hook_runtime.sh" "$tmp/hooks/fail.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 23 ]]
printf '[PASS] test-hook-isolation-v1433\n'
