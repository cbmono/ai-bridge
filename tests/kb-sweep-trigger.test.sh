#!/usr/bin/env bash
#
# kb-sweep-trigger.test.sh — the idle tick's KB sweep: `kb-sweep-due.sh` fires on exactly
# one situation, and the two documents that act on it say the same thing it does.
#
# WHY THIS IS A HARNESS AND NOT A PARAGRAPH IN project-manager.md. The trigger has FOUR
# conditions — the tick dispatched nothing, `build-kb-index.sh --check` found at least one
# ERROR, no cataloguer is in flight, and a slot is free under `maxAgentsInFlight` — and the
# loop that evaluates them is idempotent by re-reading the bundle with no memory of the last
# tick. A condition an agent re-derives each tick is one it can re-derive differently, which
# is this repo's own "a rule with no reader is not a rule". So the decision is one exit code
# and it is driven here in all four directions against a real bundle.
#
# THE CAP ASSERTION IS DRIVEN FROM THE FILE, NOT FROM A CONSTANT. `--in-flight 3` against a
# cap of 4 must be DUE and against a cap of 3 must not, on the same fixture with only
# `instance.config.json` changed — a check that only ever saw one cap would pass identically
# on a script that ignored the key.
#
# THE PROSE HALF IS GUARDED. Every document assertion is a fixed string that must be
# present; a clause whose anchor has moved fails rather than passing silently, and the
# two mutation blocks below plant the exact regression each half exists to catch.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DUE="$REPO/plugin/scripts/kb-sweep-due.sh"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
PM="$REPO/plugin/agents/project-manager.md"
CAT="$REPO/plugin/agents/cataloguer.md"
DESIGN="$REPO/docs/pm-design.md"
README="$REPO/README.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-sweep.XXXXXX")" || {
  echo "kb-sweep-trigger.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
hasf() { # <file> <fixed string> -> yes|no
  [ "$(grep -cF -- "$2" "$1")" -gt 0 ] && echo yes || echo no
}
saw() { # <haystack> <fixed string> -> yes|no
  [ "$(printf '%s\n' "$1" | grep -cF -- "$2")" -gt 0 ] && echo yes || echo no
}

finding() { # <bundle> <slug> <lesson>
  mkdir -p "$1/knowledge/findings"
  printf -- '---\ntype: Finding\ntitle: %s\nlesson: %s\nstatus: current\n---\n\nBody.\n' "$2" "$3" \
    > "$1/knowledge/findings/$2.md"
}
mkbundle() { # <dir> <cap> -> a bundle whose index checks clean
  mkdir -p "$1"
  printf '{ "org": "x", "maxAgentsInFlight": %s }\n' "$2" > "$1/instance.config.json"
  finding "$1" a-first-thing "A first thing is a first thing."
  finding "$1" a-second-thing "A second thing is a second thing."
  ( cd "$1" && bash "$BUILD" >/dev/null 2>&1 )
}
OUT=""; RC=0
due() { # <bundle> <args…> — sets $RC and $OUT. NOT a substitution: `$(…)` is a subshell,
        # so an $OUT assigned inside one never reaches the assertion that reads it.
  local b="$1"; shift
  OUT="$(bash "${MUTANT:-$DUE}" --instance "$b" "$@" 2>&1)"; RC=$?
}

echo "== the files exist at all (or every assertion below is vacuous) =="
for f in "$DUE" "$BUILD" "$PM" "$CAT" "$DESIGN" "$README"; do
  ok "$(basename "$f") exists" "$([ -f "$f" ] && echo yes || echo no)" yes
done
ok "kb-sweep-due.sh is executable" "$([ -x "$DUE" ] && echo yes || echo no)" yes

echo
echo "== a clean bundle is NOT due, however idle the tick =="
CLEAN="$TMP/clean"; mkbundle "$CLEAN" 4
ok "the fixture starts clean" "$( ( cd "$CLEAN" && bash "$BUILD" --check >/dev/null 2>&1 ); echo $?)" 0
due "$CLEAN" --dispatched 0
ok "idle + 0 errors => not due" "$RC" 1
ok "  and it says why" "$(saw "$OUT" "the index and the documents agree")" yes

echo
echo "== idle + errors => due, with the error list as the brief =="
ERR="$TMP/errs"; mkbundle "$ERR" 4
finding "$ERR" an-unindexed-thing "An unindexed thing has no row."
due "$ERR" --dispatched 0
ok "idle + errors => due" "$RC" 0
ok "  the trigger line names it an idle tick" "$(saw "$OUT" "KB SWEEP DUE: idle tick,")" yes
ok "  the trigger line carries the error count" "$(saw "$OUT" "2 error(s)")" yes
ok "  the ERROR list is in the output (the brief)" "$(saw "$OUT" "no index row")" yes
ok "  the offending document is named" "$(saw "$OUT" "an-unindexed-thing.md")" yes

echo
echo "== busy + errors => not due; the reflect path owns the KB there =="
due "$ERR" --dispatched 1
ok "one dispatch this tick => not due" "$RC" 1
ok "  and it says why" "$(saw "$OUT" "the reflect path owns the KB")" yes
due "$ERR" --dispatched 3
ok "three dispatches this tick => not due" "$RC" 1

echo
echo "== never while a cataloguer is in flight =="
due "$ERR" --dispatched 0 --cataloguer-in-flight
ok "idle + errors + a cataloguer running => not due" "$RC" 1
ok "  and it says why" "$(saw "$OUT" "a cataloguer is already in flight")" yes

echo
echo "== maxAgentsInFlight is respected, and it is READ from the config =="
due "$ERR" --dispatched 0 --in-flight 3
ok "cap 4, 3 in flight => due" "$RC" 0
due "$ERR" --dispatched 0 --in-flight 4
ok "cap 4, 4 in flight => not due" "$RC" 1
ok "  and it names both numbers" "$(saw "$OUT" "4 agent(s) in flight at the cap of 4")" yes
printf '{ "org": "x", "maxAgentsInFlight": 3 }\n' > "$ERR/instance.config.json"
due "$ERR" --dispatched 0 --in-flight 3
ok "cap 3, 3 in flight => not due (the cap moved, the answer moved)" "$RC" 1
ok "  and it names the new cap" "$(saw "$OUT" "at the cap of 3")" yes
printf '{ "org": "x", "maxAgentsInFlight": 8 }\n' > "$ERR/instance.config.json"
due "$ERR" --dispatched 0 --in-flight 3
ok "cap 8, 3 in flight => due again" "$RC" 0
rm -f "$ERR/instance.config.json"
due "$ERR" --dispatched 0 --in-flight 4
ok "no cap in any config => the documented fallback of 4 applies" "$RC" 1

echo
echo "== the error list is bounded, and says what it left out =="
BIG="$TMP/big"; mkbundle "$BIG" 4
for i in $(seq 1 25); do finding "$BIG" "a-thing-$i" "Thing $i is thing $i."; done
due "$BIG" --dispatched 0
ok "25 unindexed docs => due" "$RC" 0
ok "  the list is capped" "$(saw "$OUT" "... and 6 more")" yes
ok "  at 20 ERROR lines" "$(printf '%s\n' "$OUT" | grep -c '^  ERROR  ')" 20

echo
echo "== an answer it cannot give is 2, never a silent 1 =="
due "$TMP" --dispatched 0
ok "no knowledge/ in the instance => unknown" "$RC" 2
ok "no --dispatched at all => usage" "$(bash "$DUE" --instance "$ERR" >/dev/null 2>&1; echo $?)" 2
due "$ERR" --dispatched two
ok "a non-integer --dispatched => usage" "$RC" 2
due "$ERR" --dispatched 0 --in-flight -1
ok "a negative --in-flight => usage" "$RC" 2
due "$ERR" --dispatched 0 --sweep-anyway
ok "an unknown flag => usage" "$RC" 2
due "$TMP/no-such-bundle" --dispatched 0
ok "a missing instance directory => unknown" "$RC" 2

echo
echo "== MUTATION: a trigger that ignored idleness would be caught =="
# The mutant needs its siblings beside it — the script resolves them from its own path —
# so it goes in a scripts/ of symlinks rather than beside the real one.
MUTDIR="$TMP/scripts"; mkdir -p "$MUTDIR"
for s in build-kb-index.sh resolve-max-agents.sh resolve-config.sh; do
  ln -s "$REPO/plugin/scripts/$s" "$MUTDIR/$s"
done
MUTANT="$MUTDIR/kb-sweep-due.sh"
ok "the idle guard's anchor still exists" \
  "$([ "$(grep -c '^\[ "\$dispatched" -eq 0 \]' "$DUE")" -eq 1 ] && echo yes || echo no)" yes
sed 's/^\[ "\$dispatched" -eq 0 \]/[ "$dispatched" -ge 0 ]/' "$DUE" > "$MUTANT"
due "$ERR" --dispatched 3
ok "the mutant fires on a busy tick (so the real check is not vacuous)" "$RC" 0
MUTANT=""

echo
echo "== project-manager.md acts on the script, and only on the script =="
ok "step 7 names the script" "$(hasf "$PM" "scripts/kb-sweep-due.sh --dispatched")" yes
ok "it passes the in-flight count" "$(hasf "$PM" "--in-flight <still running>")" yes
ok "it passes the cataloguer-in-flight flag" "$(hasf "$PM" "[--cataloguer-in-flight]")" yes
ok "exit 0 dispatches the cataloguer, namespaced" "$(hasf "$PM" 'dispatch `ai-bridge:cataloguer`')" yes
ok "the error list goes into the brief verbatim" "$(hasf "$PM" "that output pasted into the brief")" yes
ok "exit 1 is silence" "$(hasf "$PM" "Exit 1 is silence: no line in the report, no dispatch")" yes
ok "the PM never re-derives the answer itself" "$(hasf "$PM" "Never re-derive the answer by running")" yes
ok "the tick-wide throttle now counts three triggers" "$(hasf "$PM" "this refresh and the KB sweep below are the")" yes
ok "the zero-delta IDLE tick is named as skipping it" "$(hasf "$PM" "A zero-delta IDLE tick (step 0.9) skips steps 1-7")" yes

echo
echo "== the brief's clauses are all present, in project-manager.md =="
for clause in \
  "at the source frontmatter" \
  "Never hand-edit \`knowledge/index.md\`" \
  "never delete a \`Finding\`" \
  "re-check to **0" \
  "Warnings are reported, not chased" \
  "One commit, as the \`cataloguer\`"; do
  ok "brief: $clause" "$(hasf "$PM" "$clause")" yes
done

echo
echo "== the ledger names the trigger and the result; AWAITING.md is untouched =="
ok "the ledger line names trigger and before/after" "$(hasf "$PM" "idle + 35 KB errors → cataloguer; errors 35 → 0")" yes
ok "both are numbers, said so" "$(hasf "$PM" "its trigger and its result, both")" yes
ok "the sweep puts nothing in AWAITING.md" "$(hasf "$PM" "It puts nothing in \`AWAITING.md\`")" yes

echo
echo "== the cataloguer knows the pass it is dispatched for =="
ok "cataloguer.md names the sweep" "$(hasf "$CAT" "A KB sweep is that check as the whole job")" yes
ok "  fix at the source frontmatter" "$(hasf "$CAT" "Fix each **at the source frontmatter**")" yes
ok "  never hand-edit index.md" "$(hasf "$CAT" "never hand-edit \`index.md\`")" yes
ok "  never delete a Finding" "$(hasf "$CAT" "never delete a \`Finding\`**")" yes
ok "  re-check to 0 errors, one commit" "$(hasf "$CAT" "re-check to 0 errors**, and commit once")" yes
ok "  warnings are reported, not chased" "$(hasf "$CAT" "Warnings are reported in your summary, not chased")" yes

echo
echo "== the script is documented where this repo documents scripts =="
ok "README's Scripts section carries a row" "$(hasf "$README" "| \`kb-sweep-due.sh\` |")" yes
ok "pm-design.md carries the reasoning" "$(hasf "$DESIGN" "### Step 7 — why an idle tick sweeps the knowledge base")" yes
ok "  and the step-7 anchor step 7 would link to" "$(hasf "$DESIGN" '<a id="step-7"></a>')" yes

echo
TOTAL=$((pass + fail))
printf '\n  %d passed, %d failed (%d assertions)\n' "$pass" "$fail" "$TOTAL"
[ "$fail" -eq 0 ] || exit 1
