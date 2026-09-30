#!/usr/bin/env bash
#
# spawn-preflight.sh [--instance DIR] — will THIS session's permission mode get a role-agent
# spawn refused? Reads the mode hooks/permission-mode.sh recorded for this very call; no
# probe, no spawn, no transcript. One line on stdout, and the exit code is the answer:
#   0 will-not-refuse   1 will-refuse (auto mode)   2 could-not-read   3 usage
# Tier human: it never changes the mode or writes a grant. Reasoning:
# dispatch-reporting-defects/task-005. Verified by tests/spawn-preflight.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "spawn-preflight: --instance needs a directory" >&2; exit 3; }
                inst="$2"; shift 2 ;;
    *) echo "Usage: $(basename "$0") [--instance DIR]" >&2; exit 3 ;;
  esac
done

unread() { echo "could-not-read: $1 — the wave goes ahead and a refusal is caught after the fact"; exit 2; }

sid="${CLAUDE_CODE_SESSION_ID:-}"
case "$sid" in
  '') unread "CLAUDE_CODE_SESSION_ID is not set in this shell" ;;
  *[!A-Za-z0-9_-]*) unread "CLAUDE_CODE_SESSION_ID is not an id" ;;
esac
rec="$inst/$AB_MODE_DIR/$sid"
[ -f "$rec" ] || unread "no permission-mode record for this session (hook not installed, or the plugin predates it)"
read -r at mode _ < "$rec" 2>/dev/null || unread "the permission-mode record is unreadable"
case "$at" in ''|*[!0-9]*) unread "the permission-mode record is malformed" ;; esac
age=$(( $(date +%s) - 10#$at ))
# The hook writes immediately before this call runs, so an old record is some EARLIER call's.
[ "$age" -ge 0 ] && [ "$age" -le 30 ] || unread "the permission-mode record is ${age}s old, not this call's"

case "$mode" in
  auto) echo "will-refuse: this session is in auto mode, and its classifier refuses a role-agent spawn"; exit 1 ;;
  default|acceptEdits|bypassPermissions|dontAsk|plan)
    echo "will-not-refuse: this session's permission mode is $mode"; exit 0 ;;
  -) unread "the hook payload carried no permission_mode" ;;
  *) unread "unrecognised permission mode '${mode:-?}'" ;;
esac
