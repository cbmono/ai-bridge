#!/usr/bin/env bash
#
# pr-body-shape.test.sh — the short form for PR bodies, review replies and progress
# reports keeps every element that was load-bearing BEFORE it got short.
#
# WHY THIS EXISTS. `CONVENTIONS.md` never asked for a long PR body: it asked for the
# task's `acceptance_criteria` with how each was verified, plus a note when a threshold
# fired. The prose accumulated by habit, and the fix is a required shape — a one-sentence
# TL;DR, the criteria as a table, threshold questions as one flagged line each, reasoning
# moved to the commit message and the task doc. The risk that fix carries is precise and
# worth a harness: "be brief" is the most plausible excuse anyone will ever have for
# dropping the CRITERIA TABLE, and the criteria table is a MERGE GATE, not decoration.
# `SCHEMA.md` clause 7 refuses clearance while one row is `✗`, `AUTONOMY.md` repeats it as
# a delegated-merge precondition, and the independent reviewer grades against exactly that
# column. A future edit that shortens the rule by one bullet would delete the gate while
# every other check in this repo stayed green.
#
# So this file does not assert "the document mentions brevity". It asserts, one by one,
# that each element the gate is made of is still NAMED AS REQUIRED:
#   * the table is required, always, and it is the criteria that go in it;
#   * `✓` means verified BY THE AUTHOR, and `✗` is the honest state, not a failure;
#   * a `✗` blocks merge-eligibility, and it says so citing `SCHEMA.md`;
#   * the `✓`/`✗` column IS the checkbox state the clearance predicate reads — pinned in
#     `SCHEMA.md` and `AUTONOMY.md` too, because a table in `CONVENTIONS.md` that no
#     consumer is told to read would be a gate nobody applies;
#   * evidence is named (a command, a test file and its tally, a run, a URL) and brevity
#     is stated to be licence to drop NARRATION, never licence to assert without evidence.
#
# AND IT PROVES IT CAN FAIL. Every assertion here is re-run against a MUTANT copy of the
# same document with the bullet it depends on deleted, and must flip to absent. A grep
# that would pass against a document with the rule cut out of it is not a check — this
# repo has shipped tests that passed for the wrong reason, and the mutation block below is
# how this one is not another. The control (the TL;DR line, which the mutation does not
# touch) must stay present in the mutant, so "the mutation deleted everything" cannot
# masquerade as a working check.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a future re-wrap does not turn this red for a
# change nobody made.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/symlink/CONVENTIONS.md"
SEED="$REPO/seed/CLAUDE.md"
SCHEMA="$REPO/symlink/SCHEMA.md"
AUTONOMY="$REPO/symlink/AUTONOMY.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-body-shape.XXXXXX")" || {
  echo "pr-body-shape.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# One line, single-spaced: phrase matching survives a re-wrap.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

# Delete the bullet that starts with <marker> — from that line to the line before the
# next top-level `- ` bullet. This is the mutation a "just make it shorter" edit would
# make, and every gate assertion below must notice it.
strip_bullet() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) && /^- / { skip=1; next }
    skip && /^- /          { skip=0 }
    !skip                  { print }
  ' "$1"
}

# Delete from the line containing <marker> to the end of its section (the next `## `).
strip_to_heading() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) { skip=1 }
    skip && /^## / { skip=0 }
    !skip { print }
  ' "$1"
}

for f in "$CONV" "$SEED" "$SCHEMA" "$AUTONOMY"; do
  [ -f "$f" ] || { echo "pr-body-shape.test: $f not found" >&2; exit 2; }
done

CONV_FLAT="$(flatten "$CONV")"
SEED_FLAT="$(flatten "$SEED")"
SCHEMA_FLAT="$(flatten "$SCHEMA")"
AUTONOMY_FLAT="$(flatten "$AUTONOMY")"

saw() { # <haystack> <fixed string> -> yes|no
  printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no
}

echo "== 1. the PR body has a stated shape: TL;DR, criteria table, flagged line =="
ok "a one-sentence TL;DR is named"        "$(saw "$CONV_FLAT" '**A one-sentence TL;DR**, first.')" yes
ok "the example shows the TL;DR line"     "$(saw "$CONV_FLAT" '**TL;DR** — one sentence')" yes
ok "the criteria go in a TABLE"           "$(saw "$CONV_FLAT" "task's \`acceptance_criteria\` as a table")" yes
ok "one row per criterion, text verbatim" "$(saw "$CONV_FLAT" 'one row per criterion, its text verbatim')" yes
ok "the example carries a table header"   "$(saw "$CONV_FLAT" '| Criterion | ✓ | Verified by |')" yes
ok "a threshold question is ONE line"     "$(saw "$CONV_FLAT" '**A short flagged line per threshold question**')" yes
ok "…and is not a section or an essay"    "$(saw "$CONV_FLAT" 'Not a section, not an essay.')" yes
ok "reasoning moves to commit + task doc" "$(saw "$CONV_FLAT" '**Reasoning goes in the commit message and the task doc.**')" yes
ok "the reader is a human deciding merge" "$(saw "$CONV_FLAT" '**human deciding whether to merge**')" yes
ok "…not an agent reconstructing work"    "$(saw "$CONV_FLAT" 'not an agent reconstructing how you worked')" yes

echo
echo "== 2. the threshold rules emit that one line, rather than their own sections =="
ok "harness growth is one ⚠️ line"        "$(saw "$CONV_FLAT" '⚠️ Needs your call: harness growth 414 lines.')" yes
ok "PR size is one ⚠️ line"               "$(saw "$CONV_FLAT" 'say so in the PR body as one `⚠️` line')" yes

echo
echo "== 3. THE GATE: the criteria table is required and blocks a merge when unmet =="
ok "the table is REQUIRED, always"        "$(saw "$CONV_FLAT" '**Required, always**')" yes
ok "it is called the merge gate"          "$(saw "$CONV_FLAT" '**The criteria table is the merge gate')" yes
ok "✓ only for what you verified"         "$(saw "$CONV_FLAT" '**Mark `✓` only for a criterion you actually verified')" yes
ok "…and the rest are marked ✗"           "$(saw "$CONV_FLAT" 'mark the rest `✗`**')" yes
ok "a ✗ blocks merge-eligibility"         "$(saw "$CONV_FLAT" 'A `✗` **blocks the PR from being merge-eligible**')" yes
ok "…citing the SCHEMA.md clause"         "$(saw "$CONV_FLAT" 'An unverified acceptance criterion blocks clearance')" yes
ok "never ✓ because the rest passed"      "$(saw "$CONV_FLAT" 'Never mark `✓` because everything else passed.')" yes
ok "it must travel with the PR"           "$(saw "$CONV_FLAT" 'it must travel with the PR, not just your own')" yes

echo
echo "== 4. the consumers are told to read that same column =="
ok "SCHEMA reads coverage from ✓/✗"       "$(saw "$SCHEMA_FLAT" 'reads *criteria coverage* from the **`✓`/`✗` column**')" yes
ok "SCHEMA still bars prose as an input"  "$(saw "$SCHEMA_FLAT" '**Free prose is never an input**')" yes
ok "SCHEMA clause 7 refuses on one ✗"     "$(saw "$SCHEMA_FLAT" "Every acceptance-criteria row in the PR body's table is \`✓\`.")" yes
ok "AUTONOMY repeats it for the merge"    "$(saw "$AUTONOMY_FLAT" "Every acceptance-criteria row in the PR body's table is \`✓\`.")" yes

echo
echo "== 5. brevity is licence to drop narration, never to assert without evidence =="
ok "short AND auditable is stated"        "$(saw "$CONV_FLAT" '**Short and auditable are the same thing here')" yes
ok "a tally is shorter than a paragraph"  "$(saw "$CONV_FLAT" 'is *shorter* than a paragraph and *more* checkable than one')" yes
ok "…because the reader can re-run it"    "$(saw "$CONV_FLAT" 'names an artifact the reader can re-run')" yes
ok "never licence to assert w/o evidence" "$(saw "$CONV_FLAT" 'licence to assert without evidence')" yes
ok "what counts as evidence is named"     "$(saw "$CONV_FLAT" 'Name the command, the test file and its tally, the CI run, or the URL you loaded.')" yes

echo
echo "== 6. review replies: one line per finding, evidence listed, nothing restated =="
ok "one line per finding fixed"           "$(saw "$CONV_FLAT" 'One line per finding **fixed**')" yes
ok "one line per finding not taken"       "$(saw "$CONV_FLAT" 'one line per finding **not taken** (with the reason)')" yes
ok "evidence as a short list"             "$(saw "$CONV_FLAT" 'the evidence as a short list at the end')" yes
ok "never restate the finding back"       "$(saw "$CONV_FLAT" '**Never restate the finding back at the reviewer**')" yes
ok "the reply is a list, not a letter"    "$(saw "$CONV_FLAT" '**The reply is a list, not a letter**')" yes

echo
echo "== 7. progress reports: outcome first, tables, decisions last and short =="
ok "lead with the outcome"                "$(saw "$SEED_FLAT" '**Lead with the outcome**')" yes
ok "tables over paragraphs"               "$(saw "$SEED_FLAT" '**Tables over paragraphs**')" yes
ok "decisions last, and short"            "$(saw "$SEED_FLAT" '**What needs a decision goes last, and short**')" yes
ok "same discipline as a PR body"         "$(saw "$SEED_FLAT" 'same discipline as a PR body')" yes
ok "reasoning lives where it is durable"  "$(saw "$SEED_FLAT" 'Reasoning belongs where it is durable')" yes
ok "the criteria table invariant is here" "$(saw "$SEED_FLAT" "The PR body carries the task's \`acceptance_criteria\` as a table, always")" yes

echo
echo "== 8. MUTATION: cut the gate bullet out and every gate assertion flips =="
# The edit this file exists to catch: someone "shortens" CONVENTIONS.md by deleting the
# bullet that carries the gate, leaving the shape bullet (and its TL;DR) intact.
strip_bullet "$CONV" '**The criteria table is the merge gate' > "$TMP/conv-no-gate.md"
MUT_FLAT="$(flatten "$TMP/conv-no-gate.md")"
ok "the mutation removed something"       "$([ "$(wc -c < "$TMP/conv-no-gate.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the TL;DR line survives it"  "$(saw "$MUT_FLAT" '**TL;DR** — one sentence')" yes
ok "CONTROL: the shape bullet survives"   "$(saw "$MUT_FLAT" '**Required, always**')" yes
ok "mutant: ✓-only-if-verified is gone"   "$(saw "$MUT_FLAT" '**Mark `✓` only for a criterion you actually verified')" no
ok "mutant: the merge block is gone"      "$(saw "$MUT_FLAT" 'A `✗` **blocks the PR from being merge-eligible**')" no
ok "mutant: the SCHEMA citation is gone"  "$(saw "$MUT_FLAT" 'An unverified acceptance criterion blocks clearance')" no
ok "mutant: short-AND-auditable is gone"  "$(saw "$MUT_FLAT" '**Short and auditable are the same thing here')" no
ok "mutant: the evidence rule is gone"    "$(saw "$MUT_FLAT" 'licence to assert without evidence')" no

echo
echo "== 9. MUTATION: cut the review bullet, and the reply rules all flip =="
strip_bullet "$CONV" '**One review per PR' > "$TMP/conv-no-reply.md"
REPLY_FLAT="$(flatten "$TMP/conv-no-reply.md")"
ok "CONTROL: the gate survives this cut"  "$(saw "$REPLY_FLAT" '**Required, always**')" yes
ok "mutant: list-not-a-letter is gone"    "$(saw "$REPLY_FLAT" '**The reply is a list, not a letter**')" no
ok "mutant: per-finding lines are gone"   "$(saw "$REPLY_FLAT" 'One line per finding **fixed**')" no
ok "mutant: don't-restate is gone"        "$(saw "$REPLY_FLAT" '**Never restate the finding back at the reviewer**')" no

echo
echo "== 10. MUTATION: cut the progress-report rules from the seed =="
# From the short-form paragraph to the end of its section — what "trim this section"
# would actually delete.
strip_to_heading "$SEED" '**And keep it short — same discipline as a PR body' > "$TMP/seed-no-report.md"
SEEDMUT_FLAT="$(flatten "$TMP/seed-no-report.md")"
ok "CONTROL: the PR-link rule survives"   "$(saw "$SEEDMUT_FLAT" 'link to the real artifacts')" yes
ok "CONTROL: the next section survives"   "$(saw "$SEEDMUT_FLAT" '## Ad-hoc requests vs. the project loop')" yes
ok "mutant: outcome-first is gone"        "$(saw "$SEEDMUT_FLAT" '**Lead with the outcome**')" no
ok "mutant: tables-over-prose is gone"    "$(saw "$SEEDMUT_FLAT" '**Tables over paragraphs**')" no
ok "mutant: decisions-last is gone"       "$(saw "$SEEDMUT_FLAT" '**What needs a decision goes last, and short**')" no

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
