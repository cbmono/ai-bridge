#!/usr/bin/env bash
#
# bg-dispatch-probe.sh — re-measures docs/pm-design.md#step-3-background: what
# `claude --bg` accepts, what it prints, how long it takes to return, and what
# `claude agents --json` says about the session afterwards.
# Probes 1-2 are argument parsing and need no auth. Probes 3-6 spend one cheap
# haiku turn in a temp cwd, need auth, and are skipped without --live; probe 6
# removes the session it made. Nothing here touches a real bundle or a .tick-lock.
# Exit 0 always: this reports, it never gates.
set -uo pipefail

LAB="$(mktemp -d)"; LIVE="${1:-}"
trap 'rm -rf "$LAB"' EXIT
say() { printf '%-46s %s\n' "$1" "$2"; }

printf 'claude %s\n\n' "$(claude --version 2>/dev/null)"
cd "$LAB" || exit

say "1 --bg with -p" "$(claude --bg -p hi </dev/null 2>&1 >/dev/null | head -1 | cut -c1-60)"
say "2 --bg --help mentions the id" \
  "$(claude --help 2>&1 | grep -c -- '--bg, --background')"

[ "$LIVE" = "--live" ] || { printf '\n(probes 3-6 need auth and one turn: re-run with --live)\n'; exit 0; }

UUID="$(python3 -c 'import uuid;print(uuid.uuid4())')"
T0=$(date +%s)
OUT="$(claude --bg 'Reply with exactly: BGPROBE_OK' --session-id "$UUID" \
        --model haiku --permission-mode bypassPermissions </dev/null 2>"$LAB/err")"
T1=$(date +%s)
ID="$(printf '%s\n' "$OUT" | sed -n 's/^backgrounded · \([0-9a-f]*\)$/\1/p')"

say "3 spawn returned after" "$((T1 - T0))s, id ${ID:-<none>}"
say "4 --session-id beside --bg" "$(grep -c 'ignoring --session-id' "$LAB/err")"

# The session is young here on purpose: `working` is the state the cap counts, and a
# probe that sampled only after it finished would never have seen one.
say "5 state while young" \
  "$(claude agents --json 2>/dev/null | python3 -c '
import json,sys
w=sys.argv[1]
for r in json.load(sys.stdin):
    if r.get("id")==w: print(r.get("state"), "· sessionId", r.get("sessionId")); break
else: print("<not listed>")' "$ID")"

[ -n "$ID" ] && claude stop "$ID" >/dev/null 2>&1
[ -n "$ID" ] && say "6 removed" "$(claude rm "$ID" 2>&1 | head -1)"
