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
# build-board.sh, its markup selected by a flag (18 files -> 17). Pre-consolidation, at 68479c1, the same
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
#
# LOWERED 2026-08-24 — the first time, and the debt above is what it pays down. The owner
# saw both HTML board layouts rendered from live data and rejected the kanban `columns`
# one outright ("not usable… just not readable"), so build-board.sh's columns markup, its
# stylesheet, its queue derivation and the `--layout` flag that selected it were DELETED
# rather than defaulted away:
#
#   6,224 / 3,454   19 files   what show-board-link.sh pinned above
#   5,918 / 3,167   19 files   -306 total, -287 code — the columns layout, gone
#
# THE FILE COUNT DOES NOT MOVE, and that is the point of pinning two numbers. Nothing was
# retired as a script; one of the four board scripts named as the reduction candidates
# above (build-board.sh, 1,156 lines) simply stopped carrying a second renderer, and is
# now 850. The ratio inverts every raise before it: 287 of the 306 lines are CODE, because
# what went was markup, CSS and a render function — not commentary.
#
# RAISED 2026-08-24, same day, folded into the same PR: the owner flagged the Depends-on
# column wrapping a two-ref cell ("023 ," on one line, "018" on the next) taller than every
# other row. Fixed with a `min-width` on `.deps` cells holding 2+ pills, sized from the
# pill's own box model (button.dep's padding/border, digit count via `ch`) plus the td's own
# padding — not `white-space:nowrap`, which would have pushed a 5-dep cell into the Task
# column, and scoped with `:has()` so a single-ref or empty cell gains no gutter:
#
#   5,918 / 3,167   19 files   what the columns deletion above lowered to
#   5,925 / 3,174   19 files   +7 total, +7 code — the two-dep column width fix
#
# WHAT THIS DISCHARGES, AND WHAT IT DOES NOT. The objective's second criterion asks a
# project to lower one of these constants, retire a named mechanism, or say plainly that
# nothing was retireable. The columns deletion above did the first two at once, and it is
# the first movement in the right direction in v3 (6,078 -> 6,190 -> 6,224 -> 5,918 ->
# 5,925); even after this small raise it lands 153 BELOW the 6,078 that opened the project,
# so the aggregate is still negative rather than merely apologised for. It does not touch
# print-board.sh, watch-board.sh or write-snapshot.sh — a terminal renderer and a local
# watcher are different MEDIA, not duplicate layouts, and deleting one of those would
# remove a capability rather than a rejected one.
# RAISED 2026-08-26 for close-project-folder.sh, and here is the bill:
#
#   5,925 / 3,174   19 files   what the two-dep column fix pinned above
#   6,285 / 3,364   20 files   +360 total, +190 code — the folder half of closeout
#                              (324/181 of it) plus write-snapshot.sh's done-project
#                              skip (+36/+9)
#
# WHAT THE 198 CODE LINES BUY, and the honest framing: this is the largest single raise
# in the file, and 181 of it is a NEW SCRIPT for something that was previously one line
# of prose — `git rm -r projects/<slug>/` in /close-project. Two things moved it out of
# prose. First, `retain: true` gives that step a SECOND outcome (keep the folder, stamp
# `deliverable_paths:`, prune working files), so it stops being one command and becomes a
# decision with a scope. Second, and decisively, THE STEP DELETES FILES: an agent
# improvising `find … -name '*.png' -delete` from a paragraph has no fixed scope, and
# prose cannot be tested. The 181 lines buy four explicit path rules, six refusals
# (non-slug argument, unknown project, wrong cwd, report-only default, non-git tree, a
# keep-set that protects declared artifacts from the prune) and 89 assertions in
# tests/close-project-folder.test.sh that drive the real thing against a real git
# fixture. The alternative was not zero lines; it was the same behaviour with no scope
# and no test.
#
# THE 9 CODE LINES IN write-snapshot.sh are the done-project `continue` plus one
# `project_stanza()` builder. The stanza was duplicated by the first draft of this
# change — the loop now has two exits, and a field added to one and not the other
# renders a retained project differently from a live one — so factoring it costs a
# function and removes the drift; it is why the code figure is +9 rather than +17. They are what makes retention affordable at all — a done project now
# costs one frontmatter parse instead of a `phases/` + `tasks/` walk — so the tick's
# per-tick work goes DOWN as this constant goes up. That is worth stating plainly,
# because a line-count gate cannot see it.
#
# STILL OWED, unchanged and now larger: the objective's second criterion asks a project
# to LOWER one of these constants. This raise does not, and the reduction candidates
# named further up (print-board.sh, watch-board.sh, write-snapshot.sh — the board
# scripts) are untouched here.

# RAISED 2026-08-26 for the per-owner board, and this is the largest single raise in the
# file. It is written here as a REPAIR, because that is what it is: PR #31 was merged at
# an intermediate commit whose constants were still a placeholder (`CEILING_TOTAL=0`),
# which left this gate red on `main` — the one failure mode a ceiling must not have, since
# a red gate is what gets commented out. The numbers below are measured on `main` AS IT
# NOW STANDS, with #30 and #31 both in it.
#
# RE-MEASURING was necessary anyway. #30 and #31 were each measured independently against
# 5,925/3,174, so neither PR's number described the tree that results from merging both:
#
#   5,925 / 3,174   19 files   the shared base both PRs measured against
#   6,285 / 3,364   20 files   after #30 (the closeout raise above), main at 0fafbeb
#   6,648 / 3,587   20 files   after #31 too, main at 2e06c5e — +363 total, +223 code
#
# Per file, so the raise can be checked rather than believed:
#
#   build-board.sh            857 -> 1,164   +307 total, +214 code
#   show-board-link.sh         34 ->    63    +29 total,   +7 code
#   write-snapshot.sh         471 ->   498    +27 total,   +2 code
#
# WHAT THE LINES BUY, and why the alternative was not fewer lines but a broken feature.
# Artifact publishing turned out to be ACCOUNT-SCOPED: exactly one account can update a
# given artifact, so two humans sharing a bundle cannot share one published board — the
# second one's publish step had been failing silently for weeks. The fix is one board per
# owner, which means each page has to carry the OTHER owners' work, which means reading
# it from the only thing both clones share: the tracked task documents at git HEAD. That
# is a config read, a git read, a frontmatter parse, a SHA-keyed cache and a rendered
# section — none of which existed, and none of which the snapshot path could be reused
# for, because a snapshot is gitignored and no clone ever holds anybody else's.
#
# THE SPLIT IS UNUSUALLY UNFLATTERING TO THE CODE FIGURE, and worth reading before
# concluding this added 223 lines of logic. Of build-board.sh's +214 code lines, **74 are
# Python docstring lines** — prose by any reasonable reading, but the code measure only
# excludes whole-line `#` comments, so every one of them counts as code here. The measure
# is a proxy and deliberately not a parser (see below); it just has to be the same proxy
# every time. The genuine logic-and-markup remainder is ~140 lines in that file, about
# half of which is the HTML and CSS of the section itself.
#
# THE 2 CODE LINES IN write-snapshot.sh are one `p_owner` read and one field in
# `project_stanza()`. The owner read sits ABOVE the done-project `continue` on purpose:
# the stanza builder introduced by the raise above is shared by BOTH loop exits, so a
# retained project must carry `owner` exactly as a live one does or the board partitions
# the two differently. It is a field off frontmatter already in memory — it opens no file
# and does not give back the skip's saving.
#
# THE DEBT ABOVE IS UNCHANGED AND THIS ENLARGES IT. write-snapshot.sh and build-board.sh
# are two of the four board scripts named as the real reduction candidates, and this task
# grew both. Nothing was retired here. The reduction this objective is owed remains owed.
#
#   6,648 / 3,587   20 files   what #32 repaired the placeholder to, on `main` at e76b9f3
#
# RAISED 2026-08-26 for the deliverables panel (task-007), and here is the bill:
#
#   6,648 / 3,587   20 files   what #32 pinned above
#   6,775 / 3,647   20 files   +127 total, +60 code
#
# Per file, so the raise can be checked rather than believed:
#
#   build-board.sh            1,164 -> 1,234   +70 total, +46 code
#   write-snapshot.sh           498 ->   555   +57 total, +14 code
#
# WHAT THE LINES BUY. write-snapshot.sh's code lines forward `deliverable_paths:` off the
# frontmatter parse every project already gets, through `project_stanza()`, for BOTH the
# done-project skip and the live path — the same one-builder-two-exits shape the owner
# field above already established, kept rather than duplicated so a retained project's
# deliverables panel and a live project's stay sourced from one place. A second pass
# (this same PR, addressing independent review) fixed a real parsing defect in the SAME
# function: an inline list's trailing `# comment` — the exact form SCHEMA.md documents
# `deliverable_paths:` with — was swallowed into the last path entry; `list_region` now
# truncates at the closing `]` before a comment can reach it. The rest of the growth here
# is comments: the field's own CARRIED-allowlist entry, and restating (rather than
# silently leaving false) the header's "never any path outside this bundle" claim now
# that `deliverable_paths` is forwarded verbatim and only shape-checked at render time.
# build-board.sh's code lines are a "Deliverables" section rendered inside the project's
# existing collapsed `<details>` (no new `<script>` — it reuses the page's one
# `data-copy`/`data-what` clipboard helper) plus `bundle_deliverable(path, slug)`, a guard
# that re-checks every entry against `/projects/<slug>/deliverables/<file>` before it can
# reach a button — the board does not trust the writer to have restricted what it
# collected, the same rule `href()` already applies to a PR URL's scheme. The same review
# pass corrected the guard itself: it used to drop a NESTED path (`site/index.html`, e.g.
# an exported research site) as if it were hostile, silently under-counting a project's
# real deliverables against what closeout stamped — it now allows any nesting below
# `deliverables/` and rejects only an empty, `.` or `..` path segment.
#
# THE DEBT ABOVE IS UNCHANGED, AGAIN. Nothing here touches print-board.sh or
# watch-board.sh, and this raise grows two of the four named reduction candidates rather
# than shrinking any of them.
#
#   6,775 / 3,647   20 files   what the raise above pinned
#   6,792 / 3,653   20 files   +17 total, +6 code
#
# Per file:
#
#   write-snapshot.sh           555 ->   572   +17 total, +6 code
#
# WHAT THE LINES BUY — still task-007, an independent-review fix round, not new scope.
# `list_region()`'s `]`-truncation (added above to stop a trailing YAML comment from
# corrupting `deliverable_paths:`) lives in a function SHARED by every list key, and
# looked for the closing `]` with no regard for quoting — so an `open_questions` or
# `advisor_notes` entry containing ordinary brackets, or a Markdown PR link in the
# `[repo#N](url)` style this bundle's own CLAUDE.md mandates for citing PR links, was
# mistaken for the list's own end, silently dropping any entry after it. That is
# `open_questions`, the one field that gates `draft -> ready` and feeds AWAITING.md.
# The +6 code lines make the scan QUOTE-AWARE (a `"` toggles quote state; a `]` inside
# quotes no longer closes the list) rather than scoping the fix to the one caller that
# exposed it, because the same defect would otherwise stay latent in `advisor_notes`,
# `pr` and any future free-text list key sharing this function. The remaining growth
# is the comment recording why the fix's scope is "every list key", not one caller.
#
# THE DEBT ABOVE IS UNCHANGED, STILL.
#
# ---- and the round after that, which gives code lines BACK -------------------
#
#   6,792 / 3,653   20 files   what the raise above pinned
#   6,803 / 3,650   20 files   +11 total, -3 CODE
#
# Per file:
#
#   write-snapshot.sh           572 ->   572    0 total, -6 code
#   build-board.sh            1,234 -> 1,245   +11 total, +3 code
#
# WHAT THE LINES BUY — task-007 again, the third independent-review round on the same
# PR. The quote-aware scan above was itself wrong, and wrong in the direction that
# matters: on ODD quote parity it found no unquoted `]`, truncated NOTHING, and folded
# the trailing YAML comment — a hand edit naming a path on the publisher's own disk —
# into the deliverable path a copy button carries on the published board. So the
# parity loop is gone, replaced by ONE `sub()` whose pattern cannot end a
# list early by construction (`[^]]*$` forces the matched `]` to be the last on the
# line, and a list's terminator always follows every `]` its entries contain). That is
# the -6 code in write-snapshot.sh, and the reason this raise is mostly a refund.
#
# build-board.sh's +3 code is the price of the one case that strip declines — a comment
# carrying a `]` of its own, where stripping could end a list early — which leaves the
# value uncorrected rather than truncated. `bundle_deliverable()` now rejects a path
# carrying a `#`: no path closeout stamps can contain one, every YAML comment starts
# with one, and this is the last point before a published page. Fixing the parser and
# guarding the render are not redundant here — the parser keeps SNAPSHOT.json honest,
# the guard is what holds when a document is malformed in a way no parser will fix.
#
# THE DEBT ABOVE IS UNCHANGED, ONCE MORE.
CEILING_TOTAL=6803
CEILING_CODE=3650

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
