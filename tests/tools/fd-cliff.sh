#!/usr/bin/env bash
#
# fd-cliff.sh — reproduces the tests/harness-read-paths.test.sh hang in seconds.
# A. the mechanism, with no harness content: this bash leaks one fd per `< <( )`, and
#    past ~254 of them a fork stops returning. B. the margin: the smallest number of
#    INHERITED fds that makes the real harness hang. C. the stack of the spinning child.
# Exit: 0 the harness clears the cliff · 1 it still hangs · 2 refused.
# Not a `*.test.sh`: part A fails on any bash 3.2 by design. Measurements: ai-bridge-v3/task-042.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TESTS="$(cd "$HERE/.." && pwd)"
HARNESS="$TESTS/harness-read-paths.test.sh"
BOUND="${FD_CLIFF_BOUND:-45}"
SPARES="${FD_CLIFF_SPARES:-0 1 2 4 8}"
[ -r "$HARNESS" ] || { echo "fd-cliff: no $HARNESS" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fd-cliff.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' "$(bash --version | head -1) at $(command -v bash) · ulimit -n $(ulimit -n)"
echo

# snapshot <tag> <pgid> — the tree, and a sample of whatever in it is burning a core.
snapshot() {
  ps -axo pid,ppid,pgid,stat,%cpu,etime,command | awk -v g="$2" '$3==g' > "$TMP/tree.$1"
  command -v sample >/dev/null 2>&1 || return 0
  awk '$4 ~ /R/ {print $1}' "$TMP/tree.$1" | while read -r q; do
    sample "$q" 2 -f "$TMP/sample.$1.$q" >/dev/null 2>&1
  done
}

# bounded <tag> <outfile> <cmd>... — every probe in here runs through this, because the
# thing being probed is a fork that never returns and a synchronous call to it would hang
# this script too. Its own process group, so the deadline reaches the spinning grandchild
# and not just its shell — knowledge/findings/a-per-harness-bound-must-kill-the-process-group.
bounded() {
  local tag="$1" out="$2" pid wd rc
  shift 2
  perl -e 'setpgrp(0,0); exec @ARGV' "$@" > "$out" 2>&1 &
  pid=$!
  # One line, and it stays one: tests/background-teardown.test.sh reads a watchdog only
  # where the sleep, the kill and the `>/dev/null` sit on the spawn's own logical line.
  ( sleep "$BOUND"; kill -0 "$pid" 2>/dev/null && snapshot "$tag" "$pid"; kill -9 -"$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  disown "$wd" 2>/dev/null
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$wd" 2>/dev/null
  return "$rc"
}

# --- A. the mechanism, standalone ------------------------------------------------------
echo "== A. one leaked fd per process substitution, $BOUND s bound, killed by process GROUP =="
cat > "$TMP/leak.sh" <<'LEAK'
#!/usr/bin/env bash
f() { local i l
      for i in $(seq 1 "$1"); do while IFS= read -r l; do :; done < <(printf 'a\n'); done
      ls /dev/fd | wc -l | tr -d ' '; }
out="$(f "$1")"; rc=$?
printf 'open=%-4s capture rc=%s\n' "${out:--}" "$rc"
LEAK
for n in 1 64 253 254 300; do
  bounded "A$n" "$TMP/a.$n" bash "$TMP/leak.sh" "$n"
  line="$(tail -1 "$TMP/a.$n" 2>/dev/null)"
  printf '  %4s procsubs -> %s\n' "$n" "${line:-HUNG past ${BOUND}s — the fork never returned}"
done
echo

# --- B. the margin on the real harness -------------------------------------------------
# run_one in tests/run.sh captures the harness with out="$(bash "$f" 2>&1)"; the spare fds
# stand in for anything the pool happens to leave open, which is what moves the peak.
cat > "$TMP/inner.sh" <<'INNER'
#!/usr/bin/env bash
n="$1"; h="$2"; i=0
while [ "$i" -lt "$n" ]; do eval "exec $(( 20 + i ))</dev/null"; i=$(( i + 1 )); done
if out="$(bash "$h" 2>&1)"; then rc=0; else rc=$?; fi
printf 'rc=%s %s\n' "$rc" "$(printf '%s\n' "$out" | tail -1)"
INNER

echo "== B. the real harness, $BOUND s bound, killed by process GROUP =="
first_hang=""
sig=""
for n in $SPARES; do
  start=$(date +%s)
  bounded "$n" "$TMP/out.$n" bash "$TMP/inner.sh" "$n" "$HARNESS"
  if grep -qE 'rc=0 pass=[0-9]+ fail=0' "$TMP/out.$n" 2>/dev/null; then
    printf '  %2s spare fds -> green in %ss\n' "$n" "$(( $(date +%s) - start ))"
  else
    printf '  %2s spare fds -> HUNG past %ss\n' "$n" "$BOUND"
    [ -n "$first_hang" ] || first_hang="$n"
    [ -n "$sig" ] || sig="$(cat "$TMP/sample.$n".* 2>/dev/null | grep -m1 -E '_notify_fork_child')"
  fi
done
echo

# --- C. the verdict --------------------------------------------------------------------
if [ -z "$first_hang" ]; then
  echo "PASS — no spare-fd count in '$SPARES' reaches the cliff."
  exit 0
fi
echo "FAIL — $first_hang inherited fd(s) are enough to hang the harness."
[ -s "$TMP/tree.$first_hang" ] && sed 's/^/    /' "$TMP/tree.$first_hang"
[ -n "$sig" ] && printf '    spinning child: %s\n' "$(printf '%s' "$sig" | sed 's/^ *//')"
exit 1
