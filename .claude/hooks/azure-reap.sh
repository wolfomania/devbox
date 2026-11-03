#!/bin/bash
# SessionStart hook: in cloud sessions only, delete test VMs older than 3 hours that an
# earlier (expired or forgotten) session left running. Runs in the background so the
# session start is never delayed, and never fails the session.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
command -v az >/dev/null 2>&1 || exit 0
[ -n "${AZURE_CLIENT_SECRET:-}" ] || exit 0

script="${CLAUDE_PROJECT_DIR:-.}/scripts/azure-test-vm.sh"
[ -x "$script" ] || exit 0

nohup "$script" reap 3 >/tmp/azure-reap.log 2>&1 &
exit 0
