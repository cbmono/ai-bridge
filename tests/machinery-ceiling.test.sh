#!/usr/bin/env bash
#
# machinery-ceiling.test.sh — the shell machinery under symlink/ may not grow past the
# size it is TODAY without someone deciding to let it.
#
# WHY THIS EXISTS. The standing objective is to keep this template small enough that
# adopting the next first-party harness feature is a deletion rather than a migration.
# It carried a headline number — "symlink/ machinery under ~1,200 lines (from 3,531)" —
# and a whole project closed green, 13/13 tasks, while that number went the other way to
# 5,359 and then 6,061. Every task was defensible on its own; nothing measured the
# aggregate until the project was over, when it was too late to revisit. So the number is
# now a test, run with every other test, and it fails on the commit that crosses it
# rather than at a closeout six weeks later.
#
# THE CEILING IS THE MEASUREMENT, NOT THE ASPIRATION. It is pinned to what was actually
# measured after the two HTML renderers were consolidated — not to the ~1,200 target, and
# not to a round number. A gate that fails on the day it lands gets commented out, which
# is precisely how the ~1,200 target came to be ignored for two projects. Ratchet down
# from a true number; do not aim from a false one.
#
# RAISING IT IS ALLOWED, AND IS THE POINT. This is not a wall. A change that genuinely
# needs more lines edits the constant below IN THE SAME COMMIT and says in its PR body
# what the added lines buy. That turns growth from something nobody sees into a line in a
# diff that a reviewer has to approve — which is the only thing that was missing.
#
# TWO NUMBERS, because one of them can be gamed by deleting the thing this repo is most
# careful about. A total-lines gate rewards stripping the "why" comments that make this
# machinery maintainable — the cheapest way to pass it would be to delete exactly the
# most valuable lines. So the code-only figure is pinned separately: comments are free to
# grow, logic is not.
#
# WHAT `find` IS LOAD-BEARING. `symlink/*.sh` matches NOTHING — there are no .sh files
# directly under symlink/ — and a ceiling written against that glob measures zero and
# passes forever. That very mismatch reached this test's own acceptance criteria and was
# caught in refinement. Hence the file-count assertion first: a measurement that finds
# nothing is a failure, not a pass.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ceiling.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
le()     { [[ "$1" -le "$2" ]] && echo 0 || echo 1; }
gt()     { [[ "$1" -gt "$2" ]] && echo 0 || echo 1; }

# ---------------------------------------------------------------- the ceiling
#
# Measured 2026-08-23 in this repo, after build-artifact-board.sh was folded into
# build-board.sh behind --layout (18 files -> 17). Pre-consolidation, at 68479c1, the same
# two expressions read 6,061 and 3,408, so the honest arithmetic is:
#
#   6,061 / 3,408   before                 18 files
#   6,056 / 3,398   the consolidation      17 files   (-5 / -10)
#   6,078 / 3,410   what is pinned here    17 files   (+22 / +12)
#
# Two things that number says, and both belong here rather than in a PR nobody will read
# again. First, MERGING THE RENDERERS CUT ALMOST NOTHING: the two layouts already shared
# discovery, escaping and coercion, and what remains — markup, CSS, a decision rail — is
# genuinely different per layout. The duplication that went was structural (one hardened
# path instead of two, so a fix can no longer land in one layout and miss the other), not
# 600 lines. Second, the +22 is two defects found reviewing that merge: a numeric task id
# crashed the render, and a drifted question count rendered a button per question. Both
# blanked the whole published board. Ten of the 22 lines are the comments explaining why.
#
# So the cut this objective wants has NOT happened, and this constant does not pretend
# otherwise. What has changed is that it can no longer fail to happen quietly.
#
# RAISED 2026-08-23 for check-machinery.sh, and here is the bill:
#
#   6,078 / 3,410   17 files   what task-001 pinned
#   6,187 / 3,447   18 files   +109 total, +37 code — check-machinery.sh, a SessionStart
#                              detector for machinery symlinks that have gone dangling
#
# WHAT THE 109 LINES BUY. A plain `mv` of this checkout dangled 185 symlinks across three
# instances and the ~/.claude config layer, and nothing detected it: every script, role
# agent, command and SCHEMA.md in all three pointed at a path that no longer existed while
# the instances looked fine from the outside. The failure surfaces when something executes
# a link, which for a /pm-loop tick is mid-dispatch with agents already briefed.
#
# Only 37 of the 109 are code — four probes, the dangling test, and the template's live
# path read out of the hook's own location so the printed repair is pasteable. The other 72
# are the reasoning, including the hole this hook CANNOT close: settings.json is itself one
# of the symlinks, so a wholesale move leaves nothing registered to run any detector. That
# ratio is the argument for pinning two numbers rather than one — the growth this objective
# actually cares about is +37.
#
# AND THIS PROJECT STILL OWES A REDUCTION. The objective's second criterion is that a
# project serving it LOWERS one of these two constants before it closes. Raising them here
# does not discharge that; it enlarges it. The largest remaining candidates are the four
# board scripts — build-board, print-board, watch-board, write-snapshot, 2,342 lines
# between them — and nothing this task touched.
#
# RAISED AGAIN 2026-08-24, +3 total / +0 code, fixing a CodeRabbit review comment on
# check-machinery.sh: the printed repair command interpolated $tmpl and $root unquoted, so
# a path with whitespace or a shell metacharacter would paste into a different, wrong
# command. Two `echo` lines became `printf '%q'` (same code-line count, now quoting-safe)
# plus a 3-line comment explaining why — all three of those are comment lines, which is
# the entire +3.
#
#   6,187 / 3,447   18 files   what task-021 pinned for the detector
#   6,190 / 3,447   18 files   +3 total, +0 code — quoting fix only, no new logic
#
# RAISED 2026-08-24 for show-board-link.sh, and here is the bill:
#
#   6,190 / 3,447   18 files   what task-021 pinned above
#   6,224 / 3,454   19 files   +34 total, +7 code — a third SessionStart hook, printing
#                              the published board's URL (`boardArtifactUrl` in
#                              instance.config.json, the same key task-014's tick reads)
#                              so a human opens it without hunting for it
#
# WHAT THE 7 CODE LINES BUY. One `[ -f ] && [ -d ]` instance guard (the same signature
# check-machinery.sh and push-state.sh use), one `sed` read of a single top-level string
# field, an empty/null check, and one `echo`. The other 27 of the 34 are comments —
# largely the "why this reads that key, and only that key" and "why it prints nothing
# else" reasoning, because criterion 3 (exactly one place the URL lives) and criterion 4
# (never anything task-derived) are both invisible in a diff without it.
#
# NOT PAID DOWN ELSEWHERE, and said plainly rather than left implicit. This task's scope
# is a 7-line reader; the board scripts named above as the real reduction candidates
# (2,342 lines) are untouched here and remain someone else's task. THIS PROJECT STILL
# OWES A REDUCTION, unchanged from the note above — this raise enlarges the debt it is
# describing, not the other way around.
#
#   6,190 / 3,447   18 files   what task-021 pinned for the detector
#   6,224 / 3,454   19 files   +34 total, +7 code — show-board-link.sh
CEILING_TOTAL=6224
CEILING_CODE=3454

# Both expressions, in one place, applied to a root — so the self-test below measures a
# growing fixture with the SAME code that measures the repo. A gate whose failure path is
# never executed is not known to have one.
#
#   total — every line of every .sh under the root, i.e. exactly
#           `find symlink -name '*.sh' | xargs wc -l`. Summed with awk rather than read
#           off `tail -1`, because xargs splits a long argument list into batches and
#           then prints one `total` per batch: today's 17 files are one batch, and the
#           day that stops being true the tail-read silently reports a fraction.
#   code  — the same lines minus blanks and minus whole-line `#` comments. Not a parser:
#           a trailing comment counts as code and a CSS/JS comment inside a heredoc
#           counts as code. It only has to be the same proxy every time it runs.
total_lines() { find "$1" -name '*.sh' -exec wc -l {} + | awk '$2!="total"{s+=$1} END{print s+0}'; }
code_lines()  { find "$1" -name '*.sh' -print0 | xargs -0 cat | grep -vc '^[[:space:]]*\(#.*\)\?$'; }
file_count()  { find "$1" -name '*.sh' | wc -l | tr -d ' '; }

SRC="$REPO/symlink"
N_FILES="$(file_count "$SRC")"
TOTAL="$(total_lines "$SRC")"
CODE="$(code_lines "$SRC")"

echo "== the measurement finds the machinery at all =="
# First, because every assertion below is vacuous otherwise. `symlink/*.sh` is the
# expression that would zero this out.
assert "find locates the .sh machinery (>=10 files)" "$(gt "$N_FILES" 9)"
assert "…and they carry lines"                       "$(gt "$TOTAL" 0)"
assert "…and the glob-only form would find none" \
  "$([[ "$(ls "$SRC"/*.sh 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]] && echo 0 || echo 1)"

echo "== the ceiling =="
printf '  ..... %s files, %s total lines (ceiling %s), %s code lines (ceiling %s)\n' \
  "$N_FILES" "$TOTAL" "$CEILING_TOTAL" "$CODE" "$CEILING_CODE"
assert "total lines are at or under the ceiling"     "$(le "$TOTAL" "$CEILING_TOTAL")"
assert "code lines are at or under theirs"           "$(le "$CODE" "$CEILING_CODE")"
if [[ "$TOTAL" -gt "$CEILING_TOTAL" || "$CODE" -gt "$CEILING_CODE" ]]; then
  cat >&2 <<EOF

  symlink/ has grown past its ceiling.

    total  $TOTAL  (ceiling $CEILING_TOTAL)
    code   $CODE  (ceiling $CEILING_CODE)

  This is not a wall — it is a decision that now has to be visible. Either cut the
  lines back, or raise the constant in tests/machinery-ceiling.test.sh in the SAME
  commit and say in the PR body what the added lines buy. What is not allowed is the
  aggregate moving without anybody noticing, which is how this objective was reversed
  once already. Per-file breakdown:
EOF
  find "$SRC" -name '*.sh' -exec wc -l {} + | sort -rn | sed 's|'"$REPO"/'||' >&2
fi

echo "== the gate can actually fail =="
# A ceiling nobody has ever seen reject anything is a comment. Grow a copy and check the
# same comparison flips — this is the assertion that makes the two above mean something.
FIX="$TMP/fixture"; mkdir -p "$FIX/scripts"
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/scripts/small.sh"
assert "a tiny tree is under a real ceiling"         "$(le "$(total_lines "$FIX")" "$CEILING_TOTAL")"
# One file past the ceiling, all of it CODE — so both numbers move and both comparisons
# are exercised, not just the total.
{ echo '#!/usr/bin/env bash'; yes 'true' | head -n "$((CEILING_TOTAL + 10))"; } \
  > "$FIX/scripts/fat.sh"
assert "…and the same measurement rejects a fat one"  "$(gt "$(total_lines "$FIX")" "$CEILING_TOTAL")"
assert "…on the code figure too"                     "$(gt "$(code_lines "$FIX")" "$CEILING_CODE")"
# And the reverse: deleting comments must not buy headroom. The code figure is what
# stops that, so prove it ignores comment lines the total counts.
{ echo '#!/usr/bin/env bash'; yes '# just a comment' | head -n 500; } > "$FIX/scripts/wordy.sh"
before="$(code_lines "$FIX")"
{ echo '#!/usr/bin/env bash'; yes '# just a comment' | head -n 2000; } > "$FIX/scripts/wordy.sh"
assert "500 more comment lines do not move the code figure" \
  "$([[ "$(code_lines "$FIX")" == "$before" ]] && echo 0 || echo 1)"

echo "== the constant is a measurement, not a round number =="
# Not style policing. A round ceiling is the signature of a target someone hoped for, and
# an aspirational gate is the one that gets disabled — which is the whole history here.
assert "the total ceiling is not a round hundred"    "$([[ $((CEILING_TOTAL % 100)) -ne 0 ]] && echo 0 || echo 1)"
assert "nor is the code ceiling"                     "$([[ $((CEILING_CODE % 100)) -ne 0 ]] && echo 0 || echo 1)"

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
