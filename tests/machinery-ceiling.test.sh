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
# with one, and — this last clause was FALSE, and the two rounds below are what it cost
# — this is the last point before a published page. Fixing the parser and
# guarding the render are not redundant here — the parser keeps SNAPSHOT.json honest,
# the guard is what holds when a document is malformed in a way no parser will fix.
#
# THE DEBT ABOVE IS UNCHANGED, ONCE MORE.
#
# ---- round four: the strip moves to ONE key, and stops growing the shared helper ----
#
#   6,803 / 3,650   20 files   what the raise above pinned
#   6,812 / 3,649   20 files   +9 total, -1 CODE
#
# Per file:
#
#   write-snapshot.sh           572 ->   579    +7 total, -1 code
#   build-board.sh            1,245 -> 1,247    +2 total,  0 code
#
# WHAT THE LINES BUY — and read the two rounds above first, because this one UNDOES
# their code. Both of them fixed a trailing-comment defect from inside list_region(),
# the helper six keys share, and both broke a free-text key on the way past; the `sub()`
# the last round settled on then declined the one comment shape SCHEMA.md actually
# documents (one carrying a `]`), which left the value comment-shaped, and the entries
# are re-split on COMMAS after that — so `bundle_deliverable()`'s per-entry `#` check
# saw the `#` in one fragment while an absolute path rode out in the next one and
# rendered as a copy button. A guard that runs after the split cannot fix a defect that
# happens during it.
#
# So list_region() goes back to BYTE-IDENTICAL to main's — comment-agnostic, five
# free-text keys out of the blast radius for good — and the strip moves to the one
# consumer that can afford it, deliverable_path_entries(), whose entries are bare paths
# rather than prose. That is the -1 code: two sed expressions and a splitter reused by
# both callers, in place of three rounds of scanning logic in the shared helper.
#
# build-board.sh's +2 is comment only. The `#` check stays — SNAPSHOT.json is a file on
# disk this renderer reads back without knowing who wrote it — but the comment claiming
# it was what made the declined case safe is gone, because it never was.
#
# THE DEBT ABOVE IS UNCHANGED, A FOURTH TIME.
#
# ---- round five: the guard becomes a WHITELIST, and gives code lines back ----------
#
#   6,812 / 3,649   20 files   what the raise above pinned
#   6,842 / 3,646   20 files   +30 total, -3 CODE
#
# Per file:
#
#   write-snapshot.sh           579 ->   599   +20 total, +8 code
#   build-board.sh            1,247 -> 1,257   +10 total, -11 code
#
# WHAT THE LINES BUY, and it is the same task-007 PR a fifth time — but not the same
# fix. The four rounds above each closed the vector that was reported and left another
# of its own class, because `bundle_deliverable()` anchored a PREFIX and then listed the
# characters it knew were bad. The defeating input needed no comment, no quote and no
# bracket: `[ /projects/p/deliverables/report.md /Users/somebody/Desktop/report.md ]` is
# two paths in one value, with the right prefix, no `..` and no `#`, and it rendered
# whole into a copy button labelled `report.md`.
#
# So the guard is now ONE positive predicate over the WHOLE value — `/projects/<slug>/
# deliverables/` then one or more segments, each non-empty, not `.`/`..`, and free of
# whitespace and `#`, with no trailing remainder — which is why build-board.sh gives 11
# code lines BACK: one regex and a two-line function replace a prefix test and four
# separate rejections. The slug is checked by that same rule instead of being
# interpolated into a prefix and trusted, which also absorbs the open follow-up on an
# unvalidated slug (task-018) rather than leaving it to a later change.
#
# write-snapshot.sh's +8 code is the trailing-comment cut, which is now FIDELITY ONLY —
# safety lives entirely in the predicate above — and had to regain a property round four
# dropped: it must never remove text that could still render as a deliverable. It fires
# on a block entry line (siblings are on other lines), or where the `#` follows the
# value's closing `]` and either that `]` is whitespace-separated (the terminator shape,
# which no whitespace-free entry can contain) or nothing removed holds `/projects/`.
# Two sed expressions became that awk block; the rest of the growth is the reasoning,
# which is what a sixth round would otherwise have to rediscover.
#
# THE DEBT ABOVE IS UNCHANGED, A FIFTH TIME — though the code figure moves the right way
# for the second round running (3,650 -> 3,649 -> 3,646).
#
# ---- round six: the cut stops approximating YAML and starts agreeing with it ----
#
#   6,842 / 3,646   20 files   what the raise above pinned
#   6,876 / 3,660   20 files   +34 total, +14 code
#
#   write-snapshot.sh           599 ->   630   +31 total, +14 code
#   build-board.sh            1,257 -> 1,260    +3 total,   0 code
#
# THE PREDICATE IS NOT WHAT MOVED — it survived 65 hostile inputs unchanged and none of
# these lines touch it. What moved is the trailing-comment cut, and the reason is the
# through-line of all five rounds above: each stated a PROPERTY the cut was supposed to
# have ("cannot end a list early", "never removes text that could still render") and
# checked it by argument. Round five's was false too — measured against Ruby's Psych,
# the cut disagreed with a real parser on 5 of 35 hand-written shapes, in BOTH
# directions: `[ "…/a ] #1.md", "…/b.md" ]` has two entries (`]` and `#` are ordinary
# inside quotes) and the cut deleted the clean `…/b.md` while fabricating `…/a`;
# `[ …/a] #1.md, …/b.md ]` has ONE entry (an unquoted `]` terminates a flow sequence)
# and the cut rendered `b.md`, which is comment text.
#
# So the property is no longer a proxy for the thing: THE CUT REMOVES EXACTLY THE SPAN A
# PARSER READS AS A COMMENT — checkable against a parser instead of in review. It takes
# one left-to-right scan carrying the two facts YAML actually has here (a `#` opens a
# comment only outside a quoted scalar; a flow sequence ends at its first unquoted `]`),
# and that scan minus the shape-anchored `sed` pair it replaces is the +14 code.
# Agreement with Psych goes 27/35 -> 32/35.
#
# CORRECTED 2026-08-27, and the correction is what round seven below is about. This
# paragraph used to end "the three that remain are pre-existing splitter limits (an
# unprocessed `\"` escape, a `#` glued to `]` with no space, a mixed quoted/unquoted
# list), each reproducing identically before this change". THAT WAS FALSE, and false in
# the one direction that matters. The scan handled the `\"` escape but had no case for
# `''` — YAML's ONLY single-quote escape — so it closed a single-quoted scalar at the
# first quote of the pair and cut inside one atom: on
# `[ '…/o''brien[draft].md #2', …/clean.md ]` it rendered a FABRICATED path and deleted
# the clean sibling, on a shape the previous revision got right. A mixed quoted/unquoted
# list degraded the same way, from a safe drop to a fabrication. Neither reproduced
# before that change, so neither was pre-existing.
#
# The lesson is not "check harder". A claim about a data format is exactly the kind that
# cannot be settled in review, and the harness that settled it was never committed — so
# the property held for one round and nothing guarded it. It is committed now
# (tests/deliverable-paths-vs-yaml.test.sh), it runs against a real parser whenever the
# suite is run, and it pins the agreement count. NOT "in CI": this repo has no CI at all
# — no `.github/`, no `.gitlab-ci.yml`, no `Makefile` — so "committed" is the whole of
# the guarantee, and a heading here said otherwise until it was measured.
#
# build-board.sh's +3 total, 0 code is one header claim narrowed: "a bundle-relative
# shape is the only kind of path this page renders" overreached — the other-owners
# section renders a `/projects/<slug>/` from an unvalidated slug, which this guard does
# not cover (task-020).
#
# ---- round seven: a whitelist for the segment too, and the parser check committed ----
#
#   6,876 / 3,660   20 files   what the raise above pinned
#   6,916 / 3,662   20 files   +40 total, +2 code
#
#   write-snapshot.sh           630 ->   644   +14 total, +2 code
#   build-board.sh            1,260 -> 1,286   +26 total,  0 code
#
# TWO CODE LINES, and they are the two blockers. One is the `''` case the scan was
# missing (a peek at the next character, staying inside the scalar). The other is a
# byte-safe `ws()` helper: this awk is byte-oriented, so substr() hands back one BYTE of
# a multi-byte character, and testing that byte with `~ /[[:space:]]/` aborted the whole
# program — a legitimately stamped `Übersicht.md` did not merely fail to render, it took
# every sibling on the line with it. index() compares bytes and cannot fail.
#
# build-board.sh moves 26 lines and NONE of them is code: the segment class went from
# `[^/\s#]+` to `\w[\w.+-]*`, one line for one line. The denylist form had to have
# thought of every dangerous byte and had not thought of `:`, so
# `…/deliverables/deck.md:/Users/victim/.ssh/id_rsa` rendered whole into a copy button.
# The 26 lines are the class stated in the positive, the two permissions that carry risk
# named explicitly (`.`, and a word character in any script), and what the class COSTS —
# because the next reader's temptation is to append one more character to an exclusion
# list, and that is the move this round exists to end.
#
# THE DEBT ABOVE IS UNCHANGED, A SEVENTH TIME. The code figure has now moved by +14, -3,
# -1, -3, +14, +2 across the six raises — the machinery is not growing, the reasoning is.
#
# ---- round eight: the class was Unicode-wide by ARGUMENT, and NFD proved it was not ----
#
#   6,916 / 3,662   20 files   what the raise above pinned
#   6,939 / 3,665   20 files   +23 total, +3 code
#
#   build-board.sh            1,286 -> 1,308   +22 total, +3 code
#   write-snapshot.sh           644 ->   645    +1 total,  0 code
#
# THREE CODE LINES, and they close the round-seven raise's own claim. That raise put a
# POSITIVE segment class in — the right move, and it holds — but justified its width in
# a comment that said `\w` covers "the combining marks a macOS directory listing
# decomposes an umlaut into". IT DOES NOT: a combining mark is Unicode category M and
# `\w` is alphanumerics plus `_`. So a macOS-decomposed `Übersicht.md` — `U` + U+0308,
# a LEGITIMATELY stamped deliverable, not an attack — was dropped from the panel, with
# the count tag agreeing with the short list so nothing looked wrong. Marks are now
# stripped from the string the shape is TESTED on and kept in the string RETURNED, which
# is complete where NFC-normalising would not have been (Devanagari matras, Thai vowel
# signs and Hebrew points have no precomposed form). The third code line is the price:
# stripping marks strips them from the SLUG too, so the slug is pinned on the original
# value or `/projects/p̈/deliverables/x.md` would render as project `p`'s own.
#
# WHY NOTHING CAUGHT IT, which is the part worth carrying: the differential harness
# committed one round earlier is STRUCTURALLY BLIND to an over-rejecting predicate. It
# filters the parser's answer through the same extracted predicate, so when the
# predicate drops an entry both sides drop it and agree — an ASCII-only class leaves
# that harness 56/0 green while tests/snapshot.test.sh goes red. A differential check
# bounds DISAGREEMENT with an oracle; it cannot bound agreement that is wrong in the
# same direction on both sides. That is why the NFD case is pinned in snapshot.test.sh
# and not here.
#
# THE DEBT ABOVE IS UNCHANGED, AN EIGHTH TIME.

# RAISED 2026-08-26 for review-clearance.sh, the reviewer half of the merge gate. ONE
# bill, for this change only: the 363/223 the per-owner board left unbilled was paid by
# #32 (`e76b9f3`) and is already inside the base line below, so nothing here is carrying
# somebody else's number. Re-measured on the rebased tree with this file's own two
# expressions rather than by adding up a pre-rebase diff:
#
#   6,648 / 3,587   20 files   `main` at e76b9f3, after #32 repaired the placeholder
#   7,674 / 4,094   21 files   +1,026 total, +507 code — this change
#
# Per file, so the raise can be checked rather than believed:
#
#   review-clearance.sh         0 ->  901    +901 total, +441 code   (new file)
#   required-checks.sh        212 ->  337    +125 total,  +66 code
#
# WHAT THE CODE LINES OF review-clearance.sh BUY. A merge gate that could not tell
# "reviewed and clean" from "not reviewed". A hosted reviewer that declines exits
# SUCCESSFULLY, so its status check is green either way; three PRs went out in one tick,
# one was reviewed, two carried "Review limit reached" and merged unlooked-at, and one of
# those shipped a shell script at mode 100644 that no caller can execute. The lines are
# the tables that make the answer provider-agnostic (who is a reviewer and what its check
# is called; check names that only LOOK like one; the language of "I did not review"; the
# evidence that a review DID happen), the artifact split that treats a review object and
# a comment alike, the ordering that classifies refusal language BEFORE pinning to the
# head — the refusal quotes the head too, which is the whole trap — and five exit codes
# that each name a different way of not being cleared.
#
# THE 66 IN required-checks.sh ARE MOSTLY THE FOUR WAYS IT STILL FAILED OPEN, found by
# review of the first cut, each of them a route to `ok: N required check(s) pass` on an
# unreviewed PR: a present-but-BROKEN sibling (`[ -x ]` tests a mode bit, so the sibling
# now has to prove it RUNS), a `--match-check` answer outside the three it defines, a
# required check named for a reviewer no row owns (unknown, not CI), and clearance asked
# once for the whole PR instead of once per check (so one vendor's review cleared another
# vendor's refusal). A gate whose failure mode is silent absence is worth more lines than
# one whose failure mode is a red build.
#
# RAISED AGAIN 2026-08-27, same PR, after a second independent review found FIVE more
# routes to a false clearance. Re-measured on the same base, not added up from a diff:
#
#   7,379 / 3,955   21 files   what the first cut of this change pinned
#   7,674 / 4,094   21 files   +295 total, +139 code — the five fixes
#
# All +295 land in review-clearance.sh (606 -> 901), and the split is unusually even —
# 139 code, 156 comment — because three of the five fixes are structural rather than
# additive. WHAT THE 139 CODE LINES BUY, each one a route that cleared an UNREVIEWED PR:
#
#   1. The classifier was DEFAULT-ALLOW. Positive review evidence was never required, so
#      any artifact from the reviewer that named the head and did not read as a refusal
#      cleared — including the "Currently processing new changes in this PR" placeholder
#      the vendor posts on essentially every PR before reading anything. Clearance now
#      needs a submitted review object, the reviewer's own evidence markers, or a
#      validated verdict trailer, and a placeholder is a refusal (a NOT_YET table).
#   2. The `okf-verdict` trailer was an unvalidated SUBSTRING outranking the vendor's own
#      refusal sentinel: one appended `<!-- okf-verdict v1 -->` line turned the recorded
#      rate-limit refusal from exit 1 into exit 0, and that string ships in this repo's
#      diffs. It is now parsed as a block with required fields and a head_sha that must
#      match, and honoured only for an account named with --reviewer.
#   3. `--self-test` proved the file RUNS, not that it is COMPLETE. It sits near the top,
#      so of this file's truncation points 112 passed it and 109 of those then cleared an
#      unreviewed PR. The last line is now a completeness sentinel the self-test asserts,
#      and the test sweeps every cut point past the self-test's own block.
#   4. One malformed ERE silently disabled a whole table, because the matcher read grep's
#      output and never its status (1 = no match, 2 = bad pattern). Every row is compiled
#      up front and every match checks the status; both refuse.
#   5. SUSPECT_CHECKS missed shipped vendors — `CodeAnt AI`, `Korbit AI`, `Cursor Bug
#      Bot`, `Copilot pull request review` all read as plain CI. The rows are now by
#      SHAPE, and the test asserts invented vendor names refuse, which a list of
#      spellings that already match cannot do.
#
# THE ALTERNATIVE WAS NOT FEWER LINES. Four of the five are one-line-of-logic fixes with
# a paragraph of why; the fifth (required evidence) inverts the classifier's default and
# is the reason this file's exit 4 now has two shapes. A gate whose failure mode is
# silent absence is worth more lines than one whose failure mode is a red build.
#
# STILL OWED: the objective's second criterion asks a project to LOWER one of these
# constants. This raise does not. The reduction candidates named further up
# (print-board.sh, watch-board.sh, write-snapshot.sh) are untouched.
# RAISED AGAIN 2026-08-27, same PR, after a THIRD independent review. The nine routes it
# found were not nine defects: every one was the same primitive, classifying vendor prose
# and vendor NAMES with regex tables, which is a table that can never be finished. So the
# primitive moved to the structured API rather than being patched again. Re-measured on
# the same base:
#
#   7,674 / 4,094   21 files   what the second cut of this change pinned
#   7,747 / 4,127   21 files   +73 total, +33 code — the redirect
#
# Per file, so the raise can be checked rather than believed:
#
#   review-clearance.sh       901 ->  962    +61 total, +37 code
#   required-checks.sh        337 ->  349    +12 total,  -4 code
#
# AND +73 IS THE NET OF A REAL DELETION. Gone: the `SUSPECT_CHECKS` table and
# `suspect_check()` (a list of vendor names and review phrasings, ~45 lines), the third
# `--match-check` answer that existed only to serve it, the whole `unknown_checks` block
# in required-checks.sh, and the nine PROSE rows of the review-evidence table with their
# reasoning. Added: a second `gh` call (`/repos/{o}/{r}/pulls/{n}/reviews`, the only place
# a review's `state` and `commit_id` exist), a second rendering of an artifact body
# (`strict_body`, which strips indented code blocks as well as fenced ones and is empty
# when the fences do not balance), an exact-membership test on the API's three submitted
# states, a URL strip before the head token is looked for, and the reasoning for all of it.
#
# WHAT THE 33 CODE LINES BUY, and each of these cleared an UNREVIEWED PR before:
#   1. A required check named for a shipping code reviewer settled on its green bucket
#      with zero artifacts read — `Codex Review`, bare `Cursor`/`Copilot`/`Devin`/`PR
#      Agent`. The name is no longer asked: clearance is required on every PR.
#   2. `greptile.*` and `(qodo|codium).*` were unanchored, so `greptile-evil` was greptile.
#      Column 1 is exact logins now.
#   3. Prose evidence cleared quoted approvals and matched negated sentences
#      (`Unreviewed <sha>`, `No changes requested`), and refusal prose lost to it.
#   4. A trailer inside an indented code block, or nested in an outer HTML comment, or
#      after an unbalanced fence, validated; and an unclosed block leaked its fields.
#   5. Lowercase `pending`/`dismissed` fell through a case-sensitive skip list and were
#      then treated as submitted reviews.
#
# STILL OWED: the objective's second criterion asks a project to LOWER one of these
# constants. This raise does not, though it is the first round of this PR that deletes
# more machinery than it adds in one file. The reduction candidates named further up
# (print-board.sh, watch-board.sh, write-snapshot.sh) are untouched.

# RAISED AGAIN 2026-08-27, same PR, after a FOURTH independent review. Three routes, and
# two of them are what the redirect itself cost — worth saying plainly, because the round
# that fixes an approach is the round most likely to be described as free:
#
#   7,747 / 4,127   21 files   what the redirect pinned
#   7,891 / 4,170   21 files   +144 total, +43 code — the three fixes
#
# All +144 land in review-clearance.sh (962 -> 1,106; code 478 -> 521). required-checks.sh
# is untouched at 349.
#
# WHAT THE 43 CODE LINES BUY, each one a route to clearing an UNREVIEWED pull request:
#   1. THE TWO BODY RENDERINGS DISAGREED ABOUT WHAT A FENCE IS. The refusal side stripped
#      leading whitespace before testing for one; the clearing side treated a >=4-space or
#      tab line as an indented code block and therefore not a fence. So an INDENTED fence
#      hid the unconditional rate-limit sentinel from the refusal tables while the review
#      marker outside it cleared — and the containment this file's own comments claim
#      (strict is a SUBSET of stripped) ran backwards. One `fence_of()` now answers for
#      both, and it answers as the HOST renders: <=3 spaces is a fence, four or a tab is
#      literal text. That REPLACES two hand-rolled prefix tests rather than adding a third.
#   2. A REVIEW OBJECT THAT SAYS NOTHING IS NOT EVIDENCE ON ITS OWN, and this one is the
#      redirect's own bill. The old body-SHA pin was wrong for every reason above, but an
#      empty body cannot name a head, so it refused an empty review object as a side effect
#      of being wrong. With `commit_id` as the pin, an empty-bodied COMMENTED object at the
#      head cleared OVER the reviewer's verbatim recorded refusal at that same head.
#      `COMMENTED` is not a claim (the host mints one for any inline comment or thread
#      reply); an empty APPROVED is, but it is now decided after every artifact has been
#      read, so a refusal naming THIS head wins while an older one at another commit does
#      not — a PR skipped once still has to be able to recover.
#   3. AN ABSENT PR-AUTHOR LOGIN silently switched SCHEMA.md clause 8 off: both author
#      comparisons then tested against "", which no login equals, so the reviewer account
#      could clear a pull request it had authored itself.
#
# AND WHAT THE COMMENT LINES BUY, since 101 of the 144 are not code by this file's measure
# (69 whole-line comments, the rest blanks): two of the three are
# places where a PREVIOUS round's reasoning in this same file was wrong — the stated
# asymmetry between the two renderings, and "evidence and pinning are both structural" —
# so the correction sits where the next reader will hit it rather than in a merged PR body.
#
# STILL OWED, and this is the fifth consecutive raise from this one pull request: the
# objective's second criterion asks a project to LOWER one of these constants. It has not
# happened here. The reduction candidates named further up (print-board.sh, watch-board.sh,
# write-snapshot.sh) are untouched, and the debt is larger than when this PR opened.

# RAISED AGAIN 2026-08-27, same PR, after a FIFTH independent review — and this raise is
# almost entirely ONE FUNCTION being made to agree with the host's markdown renderer, which
# is the price of having written a renderer at all:
#
#   7,891 / 4,170   21 files   what the fifth round pinned
#   8,078 / 4,238   21 files   +187 total, +68 code — the sixth round
#
# All +187 land in review-clearance.sh (1,106 -> 1,293; code 521 -> 589). required-checks.sh
# is untouched at 349.
#
# WHAT THE 68 CODE LINES BUY, each one a reproduced route to clearing an UNREVIEWED PR:
#   1. THE FENCE RULE DID NOT MATCH THE HOST, three ways, each failing OPEN — and the round
#      before this one had already made the two renderings agree with EACH OTHER, which is
#      why this is a rewrite rather than another prefix test. The blockquote CONTAINMENT was
#      discarded (an opener at quote depth 1 paired with a closer at depth 0, so the recorded
#      refusal inside a quote-opened fence vanished — the reviewer's own idiom, since its
#      notices arrive inside a `> [!WARNING]` blockquote); TABS were never expanded to
#      four-column stops (so a body that merely quotes the verdict trailer reached the parser
#      that validates one, which outranks every refusal tier); and a closing fence's RUN
#      LENGTH and INFO STRING were ignored (a ```` opener closed by ```, which also turns an
#      odd number of markers even and slips past the unbalanced-fence net). Two hand-rolled
#      prefix tests became one scanner that measures containers and indentation in COLUMNS.
#   2. "CONTENT" WAS ANY NON-WHITESPACE BYTE, so one zero-width space or one `<!-- -->`
#      restored the previous round's empty-review route exactly. Content is now what
#      RENDERS: HTML comments and the characters that occupy no glyph are removed first.
#   3. A REFUSAL COULD BE DROPPED BEFORE IT WAS WEIGHED — a refusal that names no commit at
#      all was read as one about some other commit; a refusal filed in a non-submitted
#      review state was discarded by the state filter before the refusal tables ran; and an
#      artifact whose author the host reports as `null` was skipped rather than treated as
#      the unreadable state it is.
#   4. NOTHING CLEARS INSIDE THE CLASSIFIER LOOP any more, so the answer cannot depend on the
#      order the host streamed the artifacts in — and the ranking, including the one place a
#      refusal deliberately loses, is stated where it is applied.
#
# AND WHAT THE COMMENT LINES BUY, since 119 of the 187 are not code by this file's measure:
# the previous round's stated reason — "the rule follows the host's rendering" — was FALSE
# three ways while reading as settled. Each disagreement is now named, in the file, next to
# the branch that fixes it, because that claim is what stopped the next reader looking.
#
# STILL OWED, and this is the SIXTH consecutive raise from this one pull request: the
# objective's second criterion asks a project to LOWER one of these constants. It had not
# happened by this line. The entry below is where it does.

# LOWERED 2026-08-27, same PR, after a SIXTH independent review — the first reduction on
# this objective, and it is a reduction because the seventh round's fix was to stop
# ENUMERATING:
#
#   8,078 / 4,238   21 files   what the sixth round pinned
#   8,065 / 4,233   21 files   -13 total, -5 code — this round
#
# All of it in review-clearance.sh (1,293 -> 1,280; code 589 -> 584). required-checks.sh is
# untouched at 349, for the fourth round running.
#
# HOW A ROUND THAT CLOSED THREE MORE ROUTES CAME OUT SMALLER, which is the only interesting
# thing about these two numbers:
#   1. THE CONTENT TEST WAS INVERTED. It had been a list of invisible characters to
#      subtract; thirteen more code points, plus `&#8203;`, `[//]: # ()` and `<div></div>`,
#      walked through it. Nothing is subtracted for being known-bad now: markup is removed
#      because it is markup, and what must be LEFT is an ASCII letter or digit. One rule,
#      fewer lines, and it covers the characters nobody has found yet.
#   2. THE BLOCK MACHINE MODELS CONTAINERS BY BEING READ TWICE rather than by growing a
#      case per construct. Reading A is fences and blockquotes; reading B adds raw-HTML
#      blocks and list items; the refusal side takes the UNION and the clearing side the
#      INTERSECTION. That closed the `<details>`/`<pre>`/`<div>`/`<table>` routes and the
#      list-item route at once, made `strict ⊆ stripped` structural rather than tested, and
#      made a THIRD reading the way to cover the next construct — so the next one need not
#      grow this file either.
#   3. TWO SECOND COPIES WENT: `hits()` re-derived which table row would not compile, which
#      `validate_tables` had already done before any artifact was read, and `owners_of_check`
#      shelled out to awk twice per row for what `read` splits for free.
#   4. AND ~45 LINES OF ARCHAEOLOGY. Six rounds of "the previous cut was wrong three ways"
#      had accumulated in the header. Every RULE and its reason is still there; which round
#      found it is not, because that belongs in the task document and the KB finding.
#
# STILL OWED, in the honest accounting: 13 lines against a file that has grown by 1,280 in
# this PR is a rounding error, and the reduction candidates named further up (print-board.sh,
# watch-board.sh, write-snapshot.sh) are still untouched. What changed is the direction, and
# that the smaller file was also the closed one.

# RAISED 2026-08-27, same PR, after a SEVENTH independent review. Say it plainly: the
# previous entry was this objective's first reduction, and this entry gives most of it
# back and more.
#
#   8,065 / 4,233   21 files   what the seventh round pinned
#   8,206 / 4,266   21 files   +141 total, +33 code — this round
#
# All of it in review-clearance.sh (1,280 -> 1,421; code 584 -> 617). required-checks.sh is
# untouched at 349, for the fifth round running.
#
# WHAT THE 34 CODE LINES BUY, and the honest framing is that most of them buy ONE deletion
# that could not be made without them:
#   1. `renders_content` KNEW TWO MARKUP SHAPES — an HTML comment and a tag — and eleven
#      constructs walked through it that github.com renders blank: `[//]: # (a comment)`,
#      `[x]: /y`, `[](url)`, `![](/x.png)`, `<a href="1>2"></a>`, `<!DOCTYPE html>`,
#      `<?php ?>`, `<!ENTITY x "y">` and three more. Each was a review object with an empty
#      page that counted as a claim. The replacement is not a longer list: it removes the
#      raw-HTML productions CommonMark defines — a CLOSED set of six, five of which the
#      host distinguishes — plus the two other places the source carries bytes the page
#      never shows (a link reference definition, and a link or image DESTINATION). That is
#      ~25 of the 33, and it is the difference between a set that grows every round and one
#      that does not.
#   2. A LIST ITEM ENDS TWO WAYS, and only the dedent was modelled. `ended_item()` adds the
#      sibling marker — 4 lines that close the route that falsified the previous round's
#      central claim, plus the same test reused to bound a raw-HTML block to its container.
#   3. A COMMIT HASH IS A WHOLE TOKEN. Cutting the body on separators before matching hex
#      is 2 lines and stops every UUID reading as a commit reference.
#
# AND TWO BRANCHES CAME OUT, both found by a mutant that SURVIVED because nothing could
# make it fire: the `BI[m] > 0` guard (`ended_item(0)` is false for every line, since no
# list marker has content column 0) and the CDATA production (github.com ends one at the
# first `>` exactly as it ends a declaration — measured, recorded, and now not implemented).
# A branch no test can reach is the same defect as an assertion that cannot fail.
#
# AND ~55 COMMENT LINES BUY A RETRACTION. The previous round's stated invariant — reading A
# is contained in reading B, so the union cannot hide a refusal — was false, and it was the
# argument the whole two-reading construction rested on. A wrong reason in a header is what
# stops the next reader looking, so the correction is stated where the claim was, at the
# length it takes to be believed.
#
# THE ONE NUMBER THAT WENT DOWN INSTEAD: `tests/review-clearance.test.sh` lost the 400-body
# containment sweep and the 22-row invisible-character battery — 60-odd lines of test that
# could not fail, replaced by 152 recorded answers from github.com's own renderer, which
# is not measured here because fixtures are not `.sh`. The suite also got 25% faster.
#
# STILL OWED: the objective asks a project to LOWER one of these constants and keep it
# lowered. One round in eight did. The reduction candidates named further up
# (print-board.sh, watch-board.sh, write-snapshot.sh) remain untouched, and they are where
# a real reduction has to come from — not from this file, which is now the third thing
# every round adds to.
#
# ---- REBASED 2026-08-27 onto `main` at f70a549: THE BASE MOVED, THIS PR DID NOT ----
#
# No behaviour changed here and no line of this PR's own machinery changed. What changed is
# underneath it: #35 (task-007's deliverables panel) landed +291 total / +78 code in
# build-board.sh and write-snapshot.sh, so the base this branch is measured against is no
# longer e76b9f3.
#
#   6,648 / 3,587   20 files   e76b9f3 — the base every entry above is written against
#   6,939 / 3,665   20 files   f70a549 — after #33, #36, #37 and #35; #35 is all of the move
#   8,497 / 4,344   21 files   this branch rebased onto f70a549
#
# Re-measured with this file's own two expressions against the rebased tree, not by doing
# arithmetic on a diff. Per file — and the point of the first two rows is that they did NOT
# move, so nothing of #35's is being re-billed here:
#
#   build-board.sh            1,308 / 861   byte-identical to f70a549 — inherited, not edited
#   write-snapshot.sh           645 / 286   byte-identical to f70a549 — inherited, not edited
#   review-clearance.sh       1,421 / 617   unchanged from a65b912
#   required-checks.sh          349 / 179   unchanged from a65b912, sixth round running
#
# READ THE 8,206 ABOVE WITH THIS IN MIND, because a reader comparing the two totals will
# otherwise count a raise that did not happen. Every entry above pins a total measured
# against the pre-#35 base. This PR's own contribution is +1,558 total / +679 code and it is
# the SAME before and after the rebase: 8,206 - 6,648 = 8,497 - 6,939 = 1,558, and
# 4,266 - 3,587 = 4,344 - 3,665 = 679. The +291/+78 between the two pins is #35's, and it is
# already billed in the entry #35 added further up.
#
# THE DEBT IS STILL THE DEBT, and rebasing does not pay it: write-snapshot.sh, one of the
# three named reduction candidates, grew again on `main` while this branch was in review.
CEILING_TOTAL=8497
CEILING_CODE=4344

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
#
# IT FIRED ON A TRUE MEASUREMENT ONCE, 2026-08-27: an intermediate round-eight total came
# out at exactly 8,200. Recorded rather than quietly worked around, because "I removed a
# line to get under a guard" is the behaviour this file exists to make visible. What was
# removed was a sentence duplicated verbatim two paragraphs above it in
# `review-clearance.sh`, so the trim stands on its own; the collision is why it was noticed
# and not why it was made. Later self-review lines moved the total off it anyway.
assert "the total ceiling is not a round hundred"    "$([[ $((CEILING_TOTAL % 100)) -ne 0 ]] && echo 0 || echo 1)"
assert "nor is the code ceiling"                     "$([[ $((CEILING_CODE % 100)) -ne 0 ]] && echo 0 || echo 1)"

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
