#!/usr/bin/env bash
#
# agent-sessions.sh — what a dispatched BACKGROUND role-agent session is doing.
#
#   agent-sessions.sh state <session-id>      -> working|blocked|done|gone on stdout
#   agent-sessions.sh in-flight <bundle-root> -> how many recorded sessions still hold a
#                                                slot, on stdout; one line per recorded
#                                                session on stderr
#
# Exit 0 answered · 2 unknown (no `claude`, no `python3`, unreadable JSON) — and unknown is
# never a zero, because "nothing is running" is what a broken read and an idle loop both
# look like. Reasoning: docs/pm-design.md#step-3-background.
# Verified by tests/background-dispatch.test.sh.
set -uo pipefail

usage() { sed -n '3,7p' "$0" >&2; exit 2; }
[ $# -ge 1 ] || usage

command -v python3 >/dev/null 2>&1 || {
  echo "agent-sessions: python3 is required to read \`claude agents --json\`" >&2; exit 2; }

# `--all` keeps a COMPLETED session in the listing, which is what makes `done` and `gone`
# two different answers: without it a finished agent is indistinguishable from one that
# never started, and the tick would read a clean exit as a dispatch that vanished.
sessions_json() {
  command -v claude >/dev/null 2>&1 || return 1
  claude agents --json --all 2>/dev/null </dev/null
}

# The short id `--bg` prints is the first field of `sessionId`, so one recorded value
# matches either spelling.
state_of() { # <session-id> <json>
  python3 -c '
import json, sys
want = sys.argv[1]
try:
    rows = json.loads(sys.argv[2])
except Exception:
    sys.exit(2)
for r in rows:
    sid = r.get("sessionId") or ""
    if want == r.get("id") or want == sid or sid.split("-")[0] == want:
        print(r.get("state") or r.get("status") or "working")
        sys.exit(0)
print("gone")
' "$1" "$2"
}

case "$1" in
  state)
    [ $# -eq 2 ] || usage
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }
    state_of "$2" "$json" || { echo "agent-sessions: could not read the session list" >&2; exit 2; }
    ;;

  in-flight)
    [ $# -eq 2 ] || usage
    root="$2"
    [ -d "$root" ] || { echo "agent-sessions: no such bundle root: $root" >&2; exit 2; }
    json="$(sessions_json)" || { echo "agent-sessions: no \`claude\` on PATH" >&2; exit 2; }

    live=0
    for task in "$root"/projects/*/tasks/*.md; do
      [ -f "$task" ] || continue
      fm="$(awk 'NR==1 && $0!="---" {exit} /^---$/ {n++; if (n==2) exit; next} n==1' "$task")"
      case "$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1)" in
        in-progress) ;;
        *) continue ;;
      esac
      sid="$(printf '%s\n' "$fm" | sed -n 's/^session:[[:space:]]*//p' | head -1 \
             | tr -d '"'"'"' ' | sed 's/#.*$//')"
      [ -n "$sid" ] || continue
      st="$(state_of "$sid" "$json")" || { echo "agent-sessions: could not read the session list" >&2; exit 2; }
      case "$st" in done|gone) ;; *) live=$((live+1)) ;; esac
      printf '%-8s %s  %s\n' "$st" "$sid" "$task" >&2
    done
    printf '%s\n' "$live"
    ;;

  -h|--help) sed -n '3,7p' "$0"; exit 0 ;;
  *) usage ;;
esac
