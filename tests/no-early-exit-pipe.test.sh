#!/usr/bin/env bash
# no-early-exit-pipe.test.sh — no test feeds `grep -q` through a pipe.
# Under `set -o pipefail` a pipe into an early-exiting reader reports a MATCH as a failure
# at random (knowledge: grep-q-under-pipefail-reports-a-match-as-a-failure). The fix is a
# here-string; this harness greps tests/ for the pipe shape so it cannot come back.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
assert() { if [ "$2" = 0 ]; then pass=$((pass+1)); echo "  PASS  $1"; else fail=$((fail+1)); echo "  FAIL  $1"; fi; }

echo "== no test pipes a printf into grep -q =="
hits="$(grep -n -E "printf '%s\\\\n' \"\\\$[0-9]\" \| grep -q" "$HERE"/*.test.sh || true)"
[ -z "$hits" ] || printf '%s\n' "$hits"
assert "no 'printf … | grep -q' in tests/" "$([ -z "$hits" ] && echo 0 || echo 1)"

echo "== the here-string form is what has()/hasnt() use =="
n="$(grep -l -E '^has\(\)  *\{ grep -q' "$HERE"/*.test.sh | wc -l | tr -d ' ')"
assert "at least a dozen harnesses define has() on a here-string ($n)" "$([ "$n" -ge 12 ] && echo 0 || echo 1)"

echo
echo "pass=$pass fail=$fail skip=0"
[ "$fail" -eq 0 ]
