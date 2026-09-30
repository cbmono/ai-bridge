#!/usr/bin/env bash
#
# spawn-preflight.sh --token TOK [--instance DIR] — reports THIS session's permission mode as of
# this very call, off the record hooks/permission-mode.sh wrote for the same TOK; no probe, no
# spawn, no transcript. It REPORTS THE MODE AND CLAIMS NO LAUNCH OUTCOME: measured 2026-09-30,
# the auto-mode classifier judges the brief's text and not the command, so no mode predicts a
# refusal. One line on stdout, and the exit code is the answer:
#   0 not-auto   1 auto   2 could-not-read   3 usage
# Tier human: it never changes the mode or writes a grant. Reasoning:
# dispatch-reporting-defects/task-005. Verified by tests/spawn-preflight.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

inst="."; token=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "spawn-preflight: --instance needs a directory" >&2; exit 3; }
                inst="$2"; shift 2 ;;
    --token) [ $# -ge 2 ] || { echo "spawn-preflight: --token needs a value" >&2; exit 3; }
             token="$2"; shift 2 ;;
    *) echo "Usage: $(basename "$0") --token TOK [--instance DIR]" >&2; exit 3 ;;
  esac
done

unread() { echo "could-not-read: $1 — the wave goes ahead either way"; exit 2; }

case "$token" in
  '') unread "no --token, so nothing correlates a record with this call" ;;
  *[!A-Za-z0-9_.:-]*) unread "the --token value is not a token" ;;
esac

sid="${CLAUDE_CODE_SESSION_ID:-}"
case "$sid" in
  '') unread "CLAUDE_CODE_SESSION_ID is not set in this shell" ;;
  *[!A-Za-z0-9_-]*) unread "CLAUDE_CODE_SESSION_ID is not an id" ;;
esac
rec="$inst/$AB_MODE_DIR/$sid"
[ -f "$rec" ] || unread "no permission-mode record for this session (hook not installed, or the plugin predates it)"
read -r at mode tok _ < "$rec" 2>/dev/null || unread "the permission-mode record is unreadable"
case "$at" in ''|*[!0-9]*) unread "the permission-mode record is malformed" ;; esac
# A timestamp proves recency, never that THIS call's refresh landed: a hook that cannot write
# leaves the previous call's record, which is recent and belongs to another invocation.
[ "${tok:-}" = "$token" ] || unread "the record is another call's — this call's refresh did not land"
age=$(( $(date +%s) - 10#$at ))
[ "$age" -ge 0 ] && [ "$age" -le 30 ] || unread "the permission-mode record is ${age}s old, not this call's"

case "$mode" in
  auto) echo "auto: this session is in auto mode — the mode the refusals were seen under, and it predicts nothing"; exit 1 ;;
  default|acceptEdits|bypassPermissions|dontAsk|plan)
    echo "not-auto: this session's permission mode is $mode — no launch outcome is claimed"; exit 0 ;;
  -) unread "the hook payload carried no permission_mode" ;;
  *) unread "unrecognised permission mode '${mode:-?}'" ;;
esac
