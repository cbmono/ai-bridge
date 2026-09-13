#!/usr/bin/env bash
# fold-answers.sh — the mechanical `open_questions → answered_questions` move.
#
# WHY IT IS NOT BASH OR AWK, and why that is asserted here. These are quoted YAML flow
# lists carrying backticks, commas, square brackets and ` --- ` — the exact shape a
# hand-rolled split was measured mis-parsing on 2026-09-12. The cases below drive one
# entry of each kind through and assert it survives WHOLE; the refusal cases assert the
# file is left byte-identical, because a half-written list is worse than no fold.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/fold-answers.sh"
command -v python3 >/dev/null 2>&1 || { echo "fold-answers.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fold-answers.XXXXXX")" || {
  echo "fold-answers.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

ok "the script exists" "$([ -f "$SH" ] && echo yes || echo no)" yes

doc() { # <path> <criteria> <open> <answered>
  printf -- '---\ntype: Task\ntitle: "T"\nstatus: draft\nacceptance_criteria: [ %s ]\nopen_questions: [ %s ]\nanswered_questions: [ %s ]\n---\n\n# Context\n\nbody\n' \
    "$2" "$3" "$4" > "$1"
}
field() { sed -n "s/^$2: //p" "$1" | head -n1; }

echo "== the move: every answered entry out, none left in both lists =="
A="$TMP/a.md"
doc "$A" '"c1"' '"Q1: colour? --- blue", "Q2: open", "Q3: moot? --- moot: superseded"' '"2020-01-01T00:00:00Z by x · Q0: old --- ok"'
OUT="$(bash "$SH" "$A" 2>&1)"; RC=$?
ok "it exits 0"                     "$RC" 0
ok "…and says how many it moved"    "$(printf '%s' "$OUT" | grep -c '^folded: 2 entries' | tr -d ' ')" 1
ok "the answered entries left open" "$(bash "$SH" --list "$A" open_questions | grep -c . | tr -d ' ')" 1
ok "…and the unanswered one stayed" "$(bash "$SH" --list "$A" open_questions)" "Q2: open"
ok "answered_questions grew by two" "$(bash "$SH" --list "$A" answered_questions | grep -c . | tr -d ' ')" 3
ok "the pre-existing entry is untouched" \
   "$(bash "$SH" --list "$A" answered_questions | head -n1)" "2020-01-01T00:00:00Z by x · Q0: old --- ok"
ok "NO entry is in both lists" \
   "$(comm -12 <(bash "$SH" --list "$A" open_questions | sort) \
               <(bash "$SH" --list "$A" answered_questions | sed 's/^[^·]*· //' | sort) | grep -c . | tr -d ' ')" 0

echo
echo "== the stamp: <ISO> by <login> · <entry VERBATIM> =="
ok "the moved entry carries an ISO stamp" \
   "$(bash "$SH" --list "$A" answered_questions | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z by .+ · ' | tr -d ' ')" 3
ok "…and the entry text verbatim after the separator" \
   "$(bash "$SH" --list "$A" answered_questions | grep -c '· Q1: colour? --- blue$' | tr -d ' ')" 1
# The login is resolved by decision-stamp.sh, never composed here — an unattributable one
# is written as `<unknown>` rather than skipped.
ok "the resolver is the source of the login" "$(grep -c 'decision-stamp.sh' "$SH" | tr -d ' ' | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and it is never bash's own guess"       "$(grep -c 'git log.*--format=%ae' "$SH" | tr -d ' ')" 0

echo
echo "== idempotent: nothing answered ⇒ exit 0, file byte-identical =="
B="$TMP/b.md"; doc "$B" '"c1"' '"Q1: still open"' ''
cp "$B" "$TMP/b.before"
ok "it exits 0"                "$(bash "$SH" "$B" >/dev/null 2>&1; echo $?)" 0
ok "…and wrote nothing"        "$(cmp -s "$B" "$TMP/b.before" && echo yes || echo no)" yes
cp "$A" "$TMP/a.before"
bash "$SH" "$A" >/dev/null 2>&1
ok "a second run over a folded doc changes nothing" "$(cmp -s "$A" "$TMP/a.before" && echo yes || echo no)" yes

echo
echo '== a REAL parser: backticks, commas, brackets and the --- separator survive whole =='
C="$TMP/c.md"
doc "$C" '"a `[<repo>#<n>](<url>)` row, with a comma"' \
         '"Q1: is `[ ]`, a comma and a ] fine? --- yes, all three"' ''
bash "$SH" "$C" >/dev/null 2>&1
ok "the criteria list is untouched" \
   "$(bash "$SH" --list "$C" acceptance_criteria)" 'a `[<repo>#<n>](<url>)` row, with a comma'
ok "…and the entry moved whole, separator and all" \
   "$(bash "$SH" --list "$C" answered_questions | sed 's/^[^·]*· //')" \
   'Q1: is `[ ]`, a comma and a ] fine? --- yes, all three'
# The whole point of the parser, asserted as a COUNT: one entry carrying a `, ` is one
# entry. A naive split on the comma returns two, and both halves are then quoted back into
# the document as separate criteria — which is the 2026-09-12 defect, silently.
ok "one entry carrying a comma is ONE entry" \
   "$(bash "$SH" --list "$C" acceptance_criteria | grep -c . | tr -d ' ')" 1
ok "…where a naive comma split would say two" \
   "$(sed -n 's/^acceptance_criteria: //p' "$C" | tr ',' '\n' | grep -c . | tr -d ' ')" 2

echo
echo "== the refusals: it would rather write NOTHING =="
D="$TMP/d.md"; doc "$D" '"c1"' '"Q1: a --- b"' ''
python3 - "$D" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("answered_questions: [  ]\n", "")
open(p, "w").write(s)
PY
cp "$D" "$TMP/d.before"
bash "$SH" "$D" >/dev/null 2>&1; RC=$?
ok "no answered_questions: key ⇒ exit 3" "$RC" 3
ok "…and the file is untouched"          "$(cmp -s "$D" "$TMP/d.before" && echo yes || echo no)" yes

E="$TMP/e.md"; printf 'no frontmatter here\n' > "$E"; cp "$E" "$TMP/e.before"
bash "$SH" "$E" >/dev/null 2>&1
ok "no frontmatter ⇒ exit 3"             "$(bash "$SH" "$E" >/dev/null 2>&1; echo $?)" 3
ok "…and the file is untouched"          "$(cmp -s "$E" "$TMP/e.before" && echo yes || echo no)" yes

F="$TMP/f.md"; doc "$F" '"c1"' '"Q1: unterminated --- yes' ''
cp "$F" "$TMP/f.before"
bash "$SH" "$F" >/dev/null 2>&1; RC=$?
ok "an unterminated list ⇒ exit 3"       "$RC" 3
ok "…and the file is untouched"          "$(cmp -s "$F" "$TMP/f.before" && echo yes || echo no)" yes

echo "== the BOTH-LISTS failure is refused at exit 4, not written =="
# The failure this script exists for: an entry that would remain in `open_questions` while
# a copy sits in `answered_questions` silently blocks the draft forever.
G="$TMP/g.md"
doc "$G" '"c1"' '"Q1: answered --- yes", "Q2: stays open"' '"2020-01-01T00:00:00Z by x · Q2: stays open"'
cp "$G" "$TMP/g.before"
bash "$SH" "$G" >/dev/null 2>&1; RC=$?
ok "the double-listing is refused"       "$RC" 4
ok "…and nothing was written"            "$(cmp -s "$G" "$TMP/g.before" && echo yes || echo no)" yes
# Exit 4 and exit 3 are different fixes: 4 is a state to reconcile, 3 is a list to repair.
ok "…and 4 is not 3"                     "$([ "$RC" != 3 ] && echo yes || echo no)" yes

echo
echo "== --list is READ-ONLY =="
H="$TMP/h.md"; doc "$H" '"c1"' '"Q1: answered --- yes"' ''
cp "$H" "$TMP/h.before"
bash "$SH" --list "$H" open_questions >/dev/null 2>&1
ok "--list writes nothing, even with an answer pending" \
   "$(cmp -s "$H" "$TMP/h.before" && echo yes || echo no)" yes
ok "…and an absent key prints nothing, at exit 0" \
   "$(bash "$SH" --list "$H" no_such_key; echo "rc=$?")" "rc=0"

echo
echo "== usage =="
ok "no argument is exit 2" "$(bash "$SH" >/dev/null 2>&1; echo $?)" 2
ok "an unreadable path is exit 2" "$(bash "$SH" "$TMP/nope.md" >/dev/null 2>&1; echo $?)" 2

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
