#!/usr/bin/env bash
# kb-sweep-due.sh — does THIS tick owe the cataloguer a knowledge/ sweep?
#
#   kb-sweep-due.sh --dispatched <n> [--in-flight <n>] [--cataloguer-in-flight] [--instance DIR]
#
# Due only when the tick dispatched nothing this round, no cataloguer is in flight, a slot
# is free under maxAgentsInFlight, and `build-kb-index.sh --check` reports >=1 ERROR.
# On 0 it prints the trigger line and the error list — the cataloguer's brief.
# Exit: 0 due · 1 not due (reason on stderr) · 2 unknown (usage, no knowledge/ here).
# Why: project-manager.md step 7, docs/pm-design.md#step-7.
set -uo pipefail

LIST_LIMIT=20
inst="."; dispatched=""; inflight=0; cat_inflight=0
need2() { [ "$1" -ge 2 ] || { echo "kb-sweep-due: $2 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance)   need2 $# "$1"; inst="$2";       shift 2 ;;
    --dispatched) need2 $# "$1"; dispatched="$2"; shift 2 ;;
    --in-flight)  need2 $# "$1"; inflight="$2";   shift 2 ;;
    --cataloguer-in-flight) cat_inflight=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" >&2; exit 2 ;;
    *) echo "kb-sweep-due: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
for pair in "dispatched:$dispatched" "in-flight:$inflight"; do
  case "${pair#*:}" in
    ""|*[!0-9]*) echo "kb-sweep-due: --${pair%%:*} wants a non-negative integer" >&2; exit 2 ;;
  esac
done
[ -d "$inst" ] || { echo "kb-sweep-due: no such instance directory: $inst" >&2; exit 2; }

not_due() { echo "kb-sweep-due: not due — $1" >&2; exit 1; }

# The self path is resolved through the symlink, not from $0: a stamped bundle's
# scripts/ holds absolute links into the template clone (resolve-max-agents.sh).
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
[ -n "$here" ] && [ -f "$here/build-kb-index.sh" ] \
  || { echo "kb-sweep-due: build-kb-index.sh not found beside this script" >&2; exit 2; }

# Cheapest gates first, so a busy tick never pays for the KB walk.
[ "$dispatched" -eq 0 ] || not_due "this tick dispatched $dispatched agent(s); the reflect path owns the KB"
[ "$cat_inflight" -eq 0 ] || not_due "a cataloguer is already in flight"
cap="$(bash "$here/resolve-max-agents.sh" --instance "$inst" 2>/dev/null)" || cap=4
[ "$inflight" -lt "$cap" ] || not_due "$inflight agent(s) in flight at the cap of $cap"

out="$(cd "$inst" && bash "$here/build-kb-index.sh" --check 2>&1)"; rc=$?
[ "$rc" -ne 2 ] || { printf '%s\n' "$out" >&2; echo "kb-sweep-due: build-kb-index.sh could not answer" >&2; exit 2; }
summary="$(printf '%s\n' "$out" | grep -E '^build-kb-index: [0-9]+ error' | tail -1)"
errors="$(printf '%s' "$summary" | sed -n 's/^build-kb-index: \([0-9]*\) error.*/\1/p')"
warns="$(printf '%s' "$summary" | sed -n 's/.*, \([0-9]*\) warning.*/\1/p')"
case "$errors" in ""|*[!0-9]*) echo "kb-sweep-due: build-kb-index.sh printed no error count" >&2; exit 2 ;; esac
[ "$errors" -gt 0 ] || not_due "$errors error(s) — the index and the documents agree"

printf 'KB SWEEP DUE: idle tick, %s error(s), %s warning(s) — dispatch the cataloguer.\n' \
  "$errors" "${warns:-0}"
printf '%s\n' "$out" | awk -v lim="$LIST_LIMIT" '
  /^  ERROR  / { n++; if (n <= lim) { print; if ((getline nxt) > 0) print nxt } next }
  END { if (n > lim) printf "  ... and %d more (build-kb-index.sh --check lists them all).\n", n - lim }'
exit 0
