#!/usr/bin/env bash
#
# record-host-rendering.test.sh — pins ai-bridge-v4/task-022's fix to
# tests/fixtures/reviewer/record-host-rendering.sh's `ask()`.
#
# THE DEFECT THIS REPLACES. `ask()` used to pipe `gh api … 2>/dev/null` straight into
# `classify`, which always answers SOMETHING that looks like a real verdict — an empty
# body reads as "hidden" (refusal/marker) or "blank" (content), a real answer for a real
# empty page and indistinguishable from one for an API call that never rendered anything
# at all. So an empty or failed `gh api` response landed in `host-rendering.txt` as a
# valid-looking verdict, and `[ -n "$verdict" ]` — the guard meant to catch exactly
# this — could never fire, because `classify` never returns empty.
#
# WHY A PARTIAL FAILURE IS THE ONE THAT MATTERS, AND HOW THIS PINS IT. A TOTAL failure
# (every call empty) is the easy case — the three non-vacuity counters in
# review-clearance.test.sh would eventually notice a corpus that is all "hidden"/"blank".
# A PARTIAL one — some subset of calls silently empty while the rest succeed — would
# quietly de-assert exactly the refusal or marker cases that landed on the failing calls,
# leaving the surrounding cases looking normal. The fix in `ask()` validates the RAW `gh
# api` response before it ever reaches `classify`, on EVERY call, not in aggregate at the
# end — so a partial failure and a total failure are the SAME failure at the point they
# happen: the very first bad call aborts the run, whether it is call 1 of 154 or call 150.
# `== a partial run aborts, not just a total one ==` below is the case that pins this: most
# calls succeed, exactly one (mid-run, not the first) comes back empty, and the whole
# recording still refuses to complete or to touch the real fixture.
#
# `gh` is replaced by a fake on PATH; `jq` and `perl` are the real ones (the script under
# test requires both, and this test does no rendering of its own to fake).
set -uo pipefail

SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer/record-host-rendering.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/record-host-rendering.XXXXXX")" || {
  echo "record-host-rendering.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2
}
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test (the script under test needs it too)"; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "perl is required to run this test (the script under test needs it too)"; exit 2; }

assert() { if [ "$2" -eq 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# --- a private copy of the script under test, run in its own directory ------------------
# `record-host-rendering.sh` resolves its own directory to find `host-rendering.txt`
# beside it (`HERE="$(cd "$(dirname "$0")" && pwd)"`), so running a COPY from a scratch
# directory means an aborted run can never touch the real, checked-in fixture — the thing
# every case below has to prove is untouched on failure.
REVIEWER="$TMP/reviewer"
mkdir -p "$REVIEWER" "$TMP/bin"
cp "$SCRIPT_SRC" "$REVIEWER/record-host-rendering.sh"
chmod +x "$REVIEWER/record-host-rendering.sh"
SCRIPT="$REVIEWER/record-host-rendering.sh"
OUT="$REVIEWER/host-rendering.txt"

# --- fake gh -----------------------------------------------------------------
# Controlled by three files under $STATE, all read fresh on every invocation:
#   mode      empty | error | partial | ok
#   fail_at   (partial only) the 1-indexed call number that answers empty
#   count     bumped on every call, so a test can tell how far the run got
export STATE="$TMP/state"
mkdir -p "$STATE"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
[ "${1:-}" = "api" ] || { echo "fake gh: unhandled command $*" >&2; exit 99; }

count_file="$STATE/count"
count=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$count_file"

mode="$(cat "$STATE/mode" 2>/dev/null || echo ok)"

case "$mode" in
  empty) exit 0 ;;                                    # simulated empty response, rc 0
  error) echo "gh: rate limit exceeded" >&2; exit 1 ;; # simulated error response
  partial)
    fail_at="$(cat "$STATE/fail_at" 2>/dev/null || echo 0)"
    [ "$count" -eq "$fail_at" ] && exit 0              # empty on exactly this one call
    ;;
esac

# "ok" path (also the non-failing calls under "partial"): find --input and echo its
# `text` field back verbatim. This is not real rendered HTML, but `classify` only greps
# for the probe phrase in whatever it is handed, so it is a fine stand-in for "the host
# answered something" — this test is about `ask()`'s handling of a BAD response, not
# about `classify`'s correctness, which review-clearance.test.sh already pins against the
# real recorded fixture.
input=""; prev=""
for a in "$@"; do
  [ "$prev" = "--input" ] && input="$a"
  prev="$a"
done
[ -n "$input" ] && jq -r .text "$input"
exit 0
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

reset_fixture() { printf 'PRE-EXISTING — must not be overwritten by an aborted run\n' > "$OUT"; }
unchanged() { [ "$(cat "$OUT")" = "PRE-EXISTING — must not be overwritten by an aborted run" ]; }

run_record() { # sets RC, STDERR
  rm -f "$STATE/count"
  STDERR="$(cd "$REVIEWER" && ./record-host-rendering.sh 2>&1 >/dev/null)"; RC=$?
}

echo "== a simulated EMPTY response aborts the run =="
reset_fixture
echo empty > "$STATE/mode"
run_record
assert "the run exits non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "…and the real fixture is untouched" "$(unchanged && echo 0 || echo 1)"
assert "…and stderr says why (empty response, not a silent classification)" \
  "$(grep -qi 'EMPTY response' <<<"$STDERR" && echo 0 || echo 1)"

echo "== a simulated ERROR response aborts the run =="
reset_fixture
echo error > "$STATE/mode"
run_record
assert "the run exits non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "…and the real fixture is untouched" "$(unchanged && echo 0 || echo 1)"
assert "…and stderr carries gh's own error text, not a swallowed one" \
  "$(grep -qF 'rate limit exceeded' <<<"$STDERR" && echo 0 || echo 1)"

echo "== a PARTIAL run aborts, not just a total one =="
# The dangerous case named in the task: most calls succeed, exactly ONE mid-run call
# comes back empty. Proves the abort is not merely "everything failed so of course it
# stopped" — some real work happened first, and the run still refuses to finish or write.
reset_fixture
printf 'partial\n' > "$STATE/mode"
printf '5\n' > "$STATE/fail_at"
run_record
assert "the run exits non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "…and the real fixture is untouched" "$(unchanged && echo 0 || echo 1)"
assert "…and at least 4 calls succeeded before the 5th one failed (this really was PARTIAL)" \
  "$([ "$(cat "$STATE/count" 2>/dev/null || echo 0)" -ge 5 ] && echo 0 || echo 1)"
assert "…and stderr identifies which case could not be classified" \
  "$(grep -qi 'could not classify\|EMPTY response' <<<"$STDERR" && echo 0 || echo 1)"

echo "== control: a run where every response is real completes and DOES record =="
# Non-vacuity: proves the three cases above are failing for the reason claimed (the bad
# response), not because this harness's fake `gh` makes every run fail regardless.
reset_fixture
echo ok > "$STATE/mode"
run_record
assert "the run exits zero" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
assert "…and it wrote real cases into the fixture" \
  "$([ "$(grep -c '^@@@ end' "$OUT" 2>/dev/null || echo 0)" -gt 100 ] && echo 0 || echo 1)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
