#!/usr/bin/env bash
#
# pr-body-clearance.test.sh — exercises precondition 3 of the delegated merge gate,
# symlink/scripts/pr-body-clearance.sh.
#
# WHAT IT HAS TO PROVE, AND WHY EACH HALF IS HERE.
#
# `tests/pr-body-shape.test.sh` — the file next door — asserts that the short-form rule
# IS NAMED IN `CONVENTIONS.md`. That is a reader for the documentation, and it is doing
# its job. It is not a reader for the thing the rule governs, which is why an agent that
# had the rule opened a 14,673-character description five hours after it merged. This
# file covers the other reader: the one that takes an actual PR body and answers.
#
# THE ANTI-LENGTH-GATE CASE IS THE ONE THAT MUST NOT REGRESS, and it is pinned twice on
# purpose. The obvious implementation of "stop the long PR bodies" is a character limit,
# and it would be WRONG: a 1,137-line change may honestly need more than a tweet, and
# `CONVENTIONS.md` bounds the body's SHAPE and never its size. A size gate would refuse
# exactly the pull requests that most need explaining, and a gate that refuses correct
# work gets switched off. So:
#
#   * BEHAVIOURALLY — a body of EXACTLY 14,673 characters, the length of the description
#     that motivated the whole task, clears when it carries both elements. Not "a long
#     body"; that specific number, so a limit set anywhere at or below it goes red here.
#   * STATICALLY — the character count is computed, printed, and never compared. No line
#     mentioning the count variable contains a test at all, and the only magnitude
#     comparison anywhere in the script is on `$#`, the argument count. "Does not gate on
#     length" is not checkable; "no threshold exists in the code" is, and this is it.
#
# THE FALSE-POSITIVE CASE THIS FILE ALSO PINS. A body that merely QUOTES the convention's
# example — which is a fenced TL;DR line above a fenced table — must NOT clear on the
# example. Fenced blocks are stripped before either test runs, and `a quoted example is
# not a body` drives that. It is the only route by which this predicate could have said
# "structure present" about a body carrying none, and being wrong in that direction is
# the only way it can be dangerous: a false "structure missing" costs a human a glance.
#
# BOTH SPELLINGS OF THE TL;DR MARKER ARE PINNED, and that is coordination, not
# thoroughness. `CONVENTIONS.md` specifies a bold `**TL;DR** —` line today;
# `ai-bridge-v5/task-007` will require the heading `## Description (TL;DR)`. A gate that
# accepted only one would refuse correct pull requests the day the other landed, so both
# clear, and this file fails if either stops clearing.
#
# `gh` is replaced by a stub on PATH, so the whole matrix runs offline. The stub answers
# from $FIX; an absent fixture is an absent thing, exactly as in review-clearance.test.sh.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/pr-body-clearance.sh"
SELFTEST_OK="pr-body-clearance: self-test ok"
HEAD_SHA="0c2592f7bb98d3de9a7a181d1762dfcaf80785d9"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"

# The description that motivated the task, to the character. A limit set anywhere at or
# below this number turns the `a very long body` case red.
INCIDENT_CHARS=14673

# --- the corpus behind the ROW bound ------------------------------------------
# THESE ARE FIXTURES, NOT A LIVE READ, AND THAT IS DELIBERATE. They were measured on
# 2026-08-30T16:24Z in bytes under `LC_ALL=C` over every acceptance-criteria row of three
# real pull requests (34 rows). Two of the three were OPEN, and #70's body was edited
# between two reads twenty-four minutes apart — its worst evidence cell went 325 -> 189
# while this change was being written. A gate calibrated against a body anyone can edit
# has no baseline at all, so the boundary values live here as constants and the harness
# never asks the host for them.
#
# The bound separates the corpus exactly: everything in #67 and #70 clears, and the three
# rows of #71 that carried shell one-liners and their own reasoning do not.
ROW_CEILING=400            # midpoint of the empty band 378-421, the widest gap
ROW_FLOOR=13               # midpoint of `see above` (9) and `CI run 1234 green` (17)
PR67_WORST_CELL=377        # largest honest cell in the corpus  -> must CLEAR
PR70_WORST_CELL=189        #                                    -> must CLEAR
PR70_SHORTEST_CELL=19      # shortest honest cell in the corpus -> must CLEAR
# #70's ROUND-2 body is the strongest single case for this ceiling, because it was
# rewritten to the house style AFTER the style was written and it is criteria-complete:
# 11 rows, longest whole ROW 264 bytes, longest evidence CELL 189. A recently-written,
# fully-evidenced body therefore sits at less than half the ceiling that catches #71 —
# so the bound is refusing bloat and not refusing thoroughness. A ceiling this case could
# not clear would be set too tight, and that is asserted below rather than asserted in a
# PR body nobody can re-run.
PR70_R2_WORST_ROW=264
PR71_BLOATED_CELLS="422 462 487"   # the three rows of #71      -> must REFUSE
# #71's evidence cells in the order they appear in its table, so a whole-table fixture
# reproduces which rows the reader names, not merely how many.
PR71_ROW_CELLS="341 317 462 334 271 298 187 340 487 422 160 266"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-body-clearance.XXXXXX")" || {
  echo "pr-body-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin" "$FIX"

# --- stub ---------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for pr-body-clearance.sh: it makes exactly one call, `gh pr view --json`.
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/gh_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    [ -f "$FIX/pr_json" ] || { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json"; exit 0 ;;
esac
echo "stub: unhandled gh $*" >&2; exit 99
STUB
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
# The real jq, unless a case asks for a reader that cannot answer.
[ -f "\$FIX/jq_broken" ] && { echo "jq: broken pipe of a parser" >&2; exit 5; }
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

# --- fixtures -----------------------------------------------------------------
body_file() { # <lines...> -> a file holding them
  local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

serve() { # <body-file> [head] — publish it as the PR the script will read
  rm -f "$FIX/gh_broken" "$FIX/jq_broken"
  "$REAL_JQ" -n --arg h "${2:-$HEAD_SHA}" --rawfile b "$1" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h, body:$b}' \
    > "$FIX/pr_json"
}

chars() { "$REAL_JQ" -Rs 'length' < "$1"; }   # code points, as the host counts them

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args...] — runs against PR 42
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -3 | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — against the previous expect()'s output
  if printf '%s' "$LAST_OUT" | grep -Fq "$2"; then
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s missing %s in: %s\n' "$1" "$2" "$(printf '%s' "$LAST_OUT" | head -3 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

says_not() { # <name> <substring> — the previous output must NOT contain it
  if printf '%s' "$LAST_OUT" | grep -Fq "$2"; then
    printf '  FAIL  %-58s unexpectedly said %s\n' "$1" "$2"; fail=$((fail+1))
  else
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  fi
}

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

TABLE_HEAD='| Criterion | ✓ | Verified by |'
TABLE_RULE='|---|---|---|'
TABLE_ROW='| the retry backs off on 429 | ✓ | `foo.test.sh` 40/0 |'

echo "== the script runs, and proves it =="
out="$("$SCRIPT" --self-test 2>&1)"; rc=$?
ok "--self-test exits 0"                 "$rc" 0
ok "--self-test prints its contract"     "$out" "$SELFTEST_OK"

# The sibling's lesson, taken whole: "IT RUNS" IS NOT "IT IS COMPLETE". A copy cut off
# below the self-test block still reaches that block, still passes it, and still prints
# the sentinel — with the classifier below the cut simply gone. So the last line of the
# file is a completeness sentinel the self-test asserts, and every cut past the self-test
# block has to fail.
#
# AND THE CONTRACT IS THE PAIR, NEVER THE EXIT CODE ALONE, which is the reason this is
# spelled out rather than checked with `ok "$rc" 2`: a copy cut inside the HEADER is a
# file of nothing but comments, which runs fine and exits 0 having decided nothing. Only
# "exit 0 AND the sentinel string on stdout" separates that from a working script, and
# that pair is exactly what `required-checks.sh` compares.
selftest_contract() { # <path> -> yes if it exits 0 AND prints the contract string
  local out rc
  out="$("$1" --self-test 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$SELFTEST_OK" ]; then echo yes; else echo no; fi
}
CUT="$TMP/cut.sh"
head -c 6000 "$SCRIPT" > "$CUT"; chmod +x "$CUT"
ok "a copy cut inside the header does not satisfy the contract" "$(selftest_contract "$CUT")" no

TOTAL_LINES="$(grep -c '' "$SCRIPT")"
ST_LINE="$(grep -n '^if \[ "\${1:-}" = "--self-test" \]' "$SCRIPT" | cut -d: -f1)"
ok "the self-test block is located" "$([ -n "$ST_LINE" ] && echo yes || echo no)" yes
for pct in 5 33 66 99; do
  n=$(( ST_LINE + ( (TOTAL_LINES - ST_LINE) * pct / 100 ) ))
  head -n "$n" "$SCRIPT" > "$CUT"; chmod +x "$CUT"
  ok "cut ${pct}% past the self-test -> refuses to vouch for itself" \
     "$(selftest_contract "$CUT")" no
done
ok "…while the intact file does vouch for itself" "$(selftest_contract "$SCRIPT")" yes

echo
echo "== both elements present: it clears, at whatever length =="
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the heading form (task-007's shape) -> clear" 0 42
says   "  ...and says both elements are there" "carries a TL;DR line and a well-formed"

serve "$(body_file '**TL;DR** — adds the gate.' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the bold form (CONVENTIONS.md's shape today) -> clear" 0 42

serve "$(body_file 'TL;DR: adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the bare-token form -> clear" 0 42

# A `✗` row is the HONEST state of an unverified criterion, and SCHEMA.md clause 7 is what
# refuses on it. This predicate must not double as that gate, or the repo has two answers
# to one question — and the second one would refuse an honestly-marked PR before a human
# ever saw why.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   '| works with two host accounts | ✗ | needs two accounts |')"
expect "a table whose row is ✗ -> still CLEAR (that is clause 7's job)" 0 42

echo
echo "== the anti-length-gate case, pinned to the incident's own number =="
# THE BODY THAT MOTIVATED THE TASK PASSES. Built to exactly 14,673 characters so that a
# limit introduced anywhere at or below the incident's length goes red here rather than
# looking like success because the motivating PR would have been caught.
LONG="$TMP/long.md"
{ printf '%s\n' '## Description (TL;DR)' 'Adds the gate.' ''
  printf '%s\n' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW"
  printf '\n'
} > "$LONG"
short_by=$(( INCIDENT_CHARS - $(chars "$LONG") ))
# `printf %*s` then a translate: pad with a run of ordinary prose characters, no newline,
# so the final count is exact.
printf '%*s' "$short_by" '' | tr ' ' 'x' >> "$LONG"
ok "the long fixture is exactly the incident's length" "$(chars "$LONG")" "$INCIDENT_CHARS"
serve "$LONG"
expect "a ${INCIDENT_CHARS}-character body with both elements -> CLEAR" 0 42
says   "  ...and reports the count as information" "body is $INCIDENT_CHARS characters"
says   "  ...saying plainly that no exit code comes from it" "no
                   exit code in this script is derived from that number"

echo
echo "== the count is INFORMATION, and the code says so structurally =="
# "Does not gate on length" is not checkable. "No threshold exists in the code" is.
marked="$(grep -n 'body_chars' "$SCRIPT" | grep -cE '(-gt|-lt|-ge|-le|-eq|-ne)|\(\(|\[\[|\[ ' || true)"
ok "no line mentioning the count contains a test" "$marked" 0
# The ONLY magnitude comparison in the whole script is the argument-count loop. Anything
# else would be a number compared against a property of the text.
mags="$(grep -nE -- '-gt|-lt|-ge|-le' "$SCRIPT" | grep -vc '"\$#"' || true)"
ok "the only magnitude comparison is on \$#"       "$mags" 0
ok "the count is printed on the clearing path"     \
   "$(serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
      "$SCRIPT" 42 2>&1 | grep -c 'characters (information only')" 1
# The awk side of the same question, because the ONE length this script does compare is
# computed there. Two comparisons read a measured length: the ceiling and the floor. A
# third would be a bound nobody measured. And the classifier is asserted never to SEE the
# body's character count at all — a stronger statement than "it is not compared", since a
# body cap can only be built out of a number the comparing code can reach.
ok "the classifier compares a length twice"        \
   "$(grep -cE 'len > ceiling|len < floor' "$SCRIPT" || true)" 2
ok "…and never sees the body's own count"          \
   "$(sed -n '/^table_scan() {/,/^}/p' "$SCRIPT" | grep -c 'body_chars' || true)" 0
# The two thresholds are pinned to the measured values HERE as well as in the script, so
# "somebody rounded it up" is a red test and not a diff nobody reads.
ok "the ceiling is the measured one"               \
   "$(grep -c "^CRITERIA_EVIDENCE_CEILING=$ROW_CEILING\$" "$SCRIPT" || true)" 1
ok "the floor is the measured one"                 \
   "$(grep -c "^CRITERIA_EVIDENCE_FLOOR=$ROW_FLOOR\$" "$SCRIPT" || true)" 1

echo
echo "== the ROW bound: the reader #66's two-sided bar never had =="
# THE RULE EXISTED AND NOTHING READ IT. `CONVENTIONS.md` bounded the evidence column on
# both sides on 2026-08-29; ai-bridge#71 breached it the next day with three rows of
# 500-600 characters, inside the machinery built to end unread rules. Everything below
# drives the reader that closes that, at the measured boundaries rather than near them.
cell() { printf '%*s' "$1" '' | tr ' ' 'x'; }   # an evidence cell of exactly <n> bytes

row_body() { # <evidence-bytes>... -> a conforming body with one criteria row per argument
  local -a lines
  lines=('## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE")
  local n i=0
  for n in "$@"; do
    i=$((i+1))
    lines+=("| criterion number $i | ✓ | $(cell "$n") |")
  done
  body_file "${lines[@]}"
}

serve "$(row_body "$PR67_WORST_CELL")"
expect "#67's largest honest cell ($PR67_WORST_CELL) -> clear" 0 42
serve "$(row_body "$PR70_WORST_CELL")"
expect "#70's largest cell ($PR70_WORST_CELL) -> clear" 0 42
serve "$(row_body "$PR70_SHORTEST_CELL")"
expect "#70's shortest cell ($PR70_SHORTEST_CELL) -> clear" 0 42
# The round-2 case, built as a WHOLE ROW of exactly 264 bytes so the number in the comment
# above is the number under test: criterion text padded out, evidence at #70's own worst
# cell. It must clear with margin, not by a byte.
r2_evidence="$(cell "$PR70_WORST_CELL")"
# The mark is 3 bytes in UTF-8 and `${#var}` counts characters, so the width is computed
# from the parts rather than from a string length that would disagree with the gate.
r2_pad=$(( PR70_R2_WORST_ROW - PR70_WORST_CELL - 23 ))
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   "| criterion $(cell "$r2_pad") | ✓ | $r2_evidence |")"
r2_row="| criterion $(cell "$r2_pad") | ✓ | $r2_evidence |"
ok "…and the fixture row really is that wide" \
   "$(printf '%s' "$r2_row" | LC_ALL=C wc -c | tr -d ' ')" "$PR70_R2_WORST_ROW"
expect "#70 round-2's worst ROW (${PR70_R2_WORST_ROW}B, cell ${PR70_WORST_CELL}B) -> clear" 0 42
for n in $PR71_BLOATED_CELLS; do
  serve "$(row_body "$n")"
  expect "#71's bloated cell ($n) -> refuse" 3 42
done

# ON the boundary, both sides, so a threshold moved by one goes red here.
serve "$(row_body "$ROW_CEILING")"
expect "exactly the ceiling ($ROW_CEILING) -> clear" 0 42
serve "$(row_body "$((ROW_CEILING + 1))")"
expect "one byte over the ceiling -> refuse" 3 42
serve "$(row_body "$ROW_FLOOR")"
expect "exactly the floor ($ROW_FLOOR) -> clear" 0 42
serve "$(row_body "$((ROW_FLOOR - 1))")"
expect "one byte under the floor -> refuse" 3 42

# THE WHOLE OF #71'S TABLE, in its own row order. This is the regression: not "a long row
# is caught" but "these three rows, and only these three, and by their index".
# shellcheck disable=SC2086
serve "$(row_body $PR71_ROW_CELLS)"
expect "#71's twelve rows -> refuse" 3 42
says   "  ...counting exactly the three that breached" "but 3 acceptance-criteria"
says   "  ...naming row 3 by index and length"  "row 3 over the CEILING at 462 bytes"
says   "  ...naming row 9 by index and length"  "row 9 over the CEILING at 487 bytes"
says   "  ...naming row 10 by index and length" "row 10 over the CEILING at 422 bytes"
says   "  ...and quoting the criterion text"    "criterion number 9"
says_not "  ...while row 1, inside the bound, is not named" "row 1 over"

echo
echo "== the bound is on ONE CELL — not the row, and never the body =="
# A row is criterion text + mark + evidence. The criterion is copied VERBATIM out of the
# task document, so an author cannot shorten it; a bound that charged for it would refuse
# a correct PR for obeying a different rule. #67's worst whole ROW is 489 bytes with a
# 377-byte cell, so this case is the corpus, not a hypothetical.
LONGCRIT="$(cell 600)"
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   "| $LONGCRIT | ✓ | \`foo.test.sh\` 40/0 |")"
expect "a 600-byte CRITERION with short evidence -> clear" 0 42
# …and the same row with the lengths swapped is the case that must refuse, which is what
# makes the one above a statement about the COLUMN rather than about leniency.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   "| a short criterion | ✓ | $LONGCRIT |")"
expect "…the same 600 bytes in the EVIDENCE cell -> refuse" 3 42

echo
echo "== the floor refuses what CONVENTIONS.md names as failing it =="
for evidence in 'ok' 'done' 'see above' 'yes' 'verified'; do
  serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                     "| the retry backs off on 429 | ✓ | $evidence |")"
  expect "evidence '$evidence' -> refuse" 3 42
done
says "  ...telling the author what to name instead" "Name the artifact a reader can re-run"
# …and the shortest thing the document offers as REAL evidence clears, so the floor is a
# bound and not a general demand for more words.
for evidence in '`foo.test.sh` 40/0' 'CI run 1234 green' '`shellcheck -x run.sh` clean'; do
  serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                     "| the retry backs off on 429 | ✓ | $evidence |")"
  expect "evidence '$evidence' -> clear" 0 42
done

# An EMPTY evidence cell is the one a "skip the mark column" reader would have missed
# entirely: it would take the criterion text as the evidence and clear the single row in
# the table that has no evidence at all.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   '| the retry backs off on 429 | ✓ |  |')"
expect "an EMPTY evidence cell -> refuse" 3 42
says   "  ...at length zero, not at the criterion's length" "under the FLOOR at 0 bytes"

# The mark in the last column means the evidence is somewhere this reader does not look,
# and saying that is more useful than measuring a glyph.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   '| Criterion | Verified by | ✓ |' "$TABLE_RULE" \
                   '| the retry backs off on 429 | `foo.test.sh` 40/0 | ✓ |')"
expect "the ✓ column LAST -> refuse" 3 42
says   "  ...naming that, rather than measuring the mark" "has NO evidence column"

echo
echo "== the row bound never becomes a body bound =="
# THE ANTI-LENGTH-GATE CASE, RE-RUN THROUGH THE NEW ELEMENT. The incident body clears
# above; this is the same statement made at the scale the row bound could have tempted
# someone to sum: forty rows, each just inside the ceiling, is a criteria table of ~16,000
# bytes and it clears, because nothing adds these numbers up.
# shellcheck disable=SC2046
serve "$(row_body $(for _ in $(seq 40); do printf '%s ' "$ROW_CEILING"; done))"
expect "forty rows each AT the ceiling -> clear" 0 42
says   "  ...with the total still reported as information only" "characters (information only"

# A refusal for a missing element still carries its promise WORD FOR WORD. The row bound
# is a different refusal with a different code, and it must not have edited this one.
serve "$(body_file 'No shape at all here.')"
expect "a shapeless body -> refuse on STRUCTURE" 1 42
says   "  ...with the never-on-length promise verbatim" \
       "This refuses on missing STRUCTURE, never on length: a long body carrying"
says   "  ...and it is a DIFFERENT code from the row bound" "MISSING:"

# Untrusted text: the excerpt of a criterion is the one thing from the body this script
# echoes, so an escape sequence in it must not reach the terminal.
ESC="$(printf 'a\033[31mred\033[0m criterion')"
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   "| $ESC | ✓ | ok |")"
expect "a criterion carrying an ANSI escape -> refuse" 3 42
ok "…and the escape does not survive into the message" \
   "$(printf '%s' "$LAST_OUT" | grep -c "$(printf '\033')" || true)" 0
says "  ...while the readable part of it still names the row" "red"

echo
echo "== a missing element is a refusal, and it is named =="
serve "$(body_file 'Adds the gate, and here is a lot of detail about it.' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "no TL;DR marker -> refuse" 1 42
says   "  ...naming the TL;DR line as the missing element" "MISSING: the TL;DR line"
says_not "  ...and not blaming the table, which is present" "MISSING: the acceptance-criteria table"

serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' 'Some prose, and no table.')"
expect "no criteria table -> refuse" 1 42
says   "  ...naming the table as the missing element" "MISSING: the acceptance-criteria table"
says_not "  ...and not blaming the TL;DR, which is present" "MISSING: the TL;DR line"

serve "$(body_file 'Just some prose.')"
expect "neither element -> refuse" 1 42
says   "  ...naming the TL;DR line" "MISSING: the TL;DR line"
says   "  ...and the table too"     "MISSING: the acceptance-criteria table"

serve "$(body_file '')"
expect "an EMPTY body -> refuse (readable, not unknown)" 1 42

# A table of changed files is not the criteria table, and the `✓`/`✗` column is exactly
# what tells them apart — the same column SCHEMA.md clause 7 and AUTONOMY.md read.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   '| File | Change |' '|---|---|' '| a.sh | new |')"
expect "a table with no ✓/✗ in it -> refuse" 1 42
says   "  ...saying there is nothing for the merge gate to consult" "nothing for the merge gate to consult"

# GitHub renders NO TABLE when the delimiter row's cell count differs from the header's,
# so a body like this shows the reader a wall of pipes. Refusing it is the safe direction.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   "$TABLE_HEAD" '|---|---|' "$TABLE_ROW")"
expect "a table the host would not render -> refuse" 1 42

serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE")"
expect "a table header with no data row -> refuse" 1 42

# An escaped pipe is CONTENT in GFM, and counting it as a cell boundary would refuse a
# table the host renders perfectly — a false "structure missing" on a correct PR, which
# is the failure that gets a gate switched off.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   '| Criterion | \| | Verified by |' "$TABLE_RULE" \
                   '| a cell with a \| in it | ✓ | `foo.test.sh` 40/0 |')"
expect "a table whose cells escape a pipe -> clear" 0 42

echo
echo "== every text match fails in the SAFE direction =="
# A false "structure missing" costs a human a glance. A false "structure present" would
# clear a body nobody can read — so the TL;DR patterns are anchored at the start of a
# line, and a sentence that merely MENTIONS the rule does not satisfy it.
serve "$(body_file 'This change follows the TL;DR rule in CONVENTIONS.md closely.' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a mid-sentence mention of TL;DR does not count -> refuse" 1 42

# THREE CASES FROM THE REVIEW OF THIS PR (ai-bridge#65), all in the dangerous direction —
# each one is a body the first cut CLEARED and a human could not have read as shaped.
serve "$(body_file '## Is the TL;DR rule required?' 'Some discussion of it.' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a heading that only MENTIONS TL;DR -> refuse" 1 42
says   "  ...naming the TL;DR line as missing" "MISSING: the TL;DR line"
# …while the heading forms that ARE the marker still clear, so the fix is a narrowing and
# not a break. (`## Description (TL;DR)` and `**TL;DR** —` are covered above; this is the
# bare heading.)
serve "$(body_file '## TL;DR' 'Adds the gate.' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a bare '## TL;DR' heading -> still clear" 0 42

# `|---|:|` is not a delimiter row: GitHub renders no table at all, so a marked row under
# it is not the criteria table however much it looks like one.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   '| Criterion | ✓ |' '|---|:|' '| it works | ✓ |')"
expect "a delimiter row with a non-delimiter cell -> refuse" 1 42
# …and the alignment colons GFM does allow are still a delimiter row.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                   "$TABLE_HEAD" '|:---|:---:|---:|' "$TABLE_ROW")"
expect "alignment colons in the delimiter row -> clear" 0 42

echo
echo "== a quoted example is not a body =="
# The one route to a false "structure present": `CONVENTIONS.md`'s example IS a TL;DR line
# above a criteria table, inside a fence. A body that pastes it while saying nothing of
# its own must not clear on the paste.
serve "$(body_file 'Here is the shape CONVENTIONS.md asks for:' '' '```md' \
                   '**TL;DR** — one sentence.' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" \
                   '```' '' 'Anyway, this change does some things.')"
expect "both elements present ONLY inside a code fence -> refuse" 1 42
says   "  ...naming the TL;DR line" "MISSING: the TL;DR line"
says   "  ...and the table too"     "MISSING: the acceptance-criteria table"

# A ``` inside a ````-opened fence is NOT a closer — CommonMark closes a fence only on a
# run of the same character at least as long. A toggle that closed on any fence line let
# the quoted content below it out, which is the same false "structure present" the fence
# stripper exists to prevent.
serve "$(body_file 'Here is the shape, quoted at four backticks:' '' '````md' \
                   '**TL;DR** — one sentence.' '' '```sh' 'echo nested' '```' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '````' '' 'Anyway.')"
expect "a nested fence does not close its outer fence -> refuse" 1 42

# The other half of that: real content OUTSIDE a fence still clears when the body also
# happens to contain a fence. Stripping must not eat the body.
serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' '```sh' 'echo hi' '```' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a body with a fence AND real content -> clear" 0 42

echo
echo "== unreadable is never clearance =="
serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
: > "$FIX/gh_broken"
expect "the PR cannot be fetched -> unknown, not clear" 2 42
says   "  ...saying unknown is never clearance" "unknown is never clearance"

serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
rm -f "$FIX/pr_json"
expect "no PR at all -> unknown, not clear" 2 42

# A body field the host did not send is not an empty body: one is a read that did not
# answer, the other is a PR somebody left blank, and only the second is the author's fault.
"$REAL_JQ" -n --arg h "$HEAD_SHA" \
  '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h}' > "$FIX/pr_json"
expect "no body FIELD -> unknown, not an empty body" 2 42
says   "  ...saying so in those words" "unknown rather than"

serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
: > "$FIX/jq_broken"
expect "the JSON reader cannot answer -> unknown, not clear" 2 42
rm -f "$FIX/jq_broken"

serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a head that moved under the caller -> unknown, not clear" 2 42 --head "$OTHER_SHA"
says   "  ...saying the body read is not the one verified" "not the one that was verified"

serve "$(body_file '## Description (TL;DR)' 'x' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the caller's head still matches -> clear" 0 42 --head "$HEAD_SHA"

echo
echo "== --body-file: the same verdict, before the PR is opened =="
GOOD="$(body_file '## Description (TL;DR)' 'Adds the gate.' '' \
                  "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
BAD="$(body_file 'No shape at all here.')"
expect "a conforming draft -> clear" 0 --body-file "$GOOD"
says   "  ...and reports its length too" "characters (information only"
expect "a draft with no shape -> refuse" 1 --body-file "$BAD"
expect "a draft that does not exist -> unknown, not clear" 2 --body-file "$TMP/nope.md"
expect "--body-file with a PR number too -> usage error" 2 --body-file "$GOOD" 42

echo
echo "== usage =="
rc=0; "$SCRIPT" >/dev/null 2>&1 || rc=$?
ok "no arguments -> usage error"   "$rc" 2
serve "$GOOD"
expect "an unknown option -> usage error" 2 42 --nope

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
