#!/usr/bin/env bash
#
# review-clearance.sh — assert that an independent review ARTIFACT exists on a pull
# request, at its current head. This is precondition 2 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is precondition 1, and
# calls in here for every PR it is about to clear.
#
#   Usage: scripts/review-clearance.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#                                           [--reviewer <login>] [--for-check <name>]
#          scripts/review-clearance.sh --match-check <check-name>
#          scripts/review-clearance.sh --self-test
#
# WHY THIS EXISTS — three pull requests in one tick. All three carried a GREEN reviewer
# status check. One had been reviewed; the other two carried a comment reading "Review
# limit reached. Next included review available in 44 minutes" and had been looked at by
# nothing. Both merged. One of them shipped a shell script at mode 100644 that no caller
# can execute. A hosted reviewer that DECLINES to review still exits successfully, so its
# integration reports success — correctly, on its own terms. A status check answers "did
# the integration run", never "did a review happen".
#
# So nothing here reads a check conclusion. It reads the reviewer's ARTIFACTS and asks
# whether any of them is a review OF THIS COMMIT.
#
# THE PRIMITIVE CHANGED, AND THAT IS WHAT THIS REVISION IS. Four rounds of review found
# eleven ways to a false clearance and every one was the same thing: classifying VENDOR
# PROSE and VENDOR NAMES with regex tables. Such a table must enumerate every vendor and
# every wording that will ever exist, so it is never finished — the reviewer that found
# round four's routes reported that its OWN first battery had the same blind spot as this
# file's tests. When reviewer and implementation share a blind spot, the defect is the
# primitive. So EVIDENCE AND PINNING NOW COME FROM THE STRUCTURED API:
# `/repos/{owner}/{repo}/pulls/{n}/reviews` publishes a review's `state` and its
# `commit_id`, and `gh` was already a hard dependency. That replaces "does the body happen
# to mention the head SHA", which is how every review object here used to be pinned — and
# which is precisely the property THE TRAP below gives the REFUSAL too. TEXT MATCHING
# KEEPS EXACTLY ONE JOB, DETECTING A REFUSAL, where a false positive fails CLOSED (a human
# looks at a PR that was in fact reviewed): the unbounded matching problem now sits on the
# side where being wrong is harmless, and nothing here clears a PR for its prose.
#
# THE TRAP, AND WHY THE ORDER OF THE TESTS BELOW IS LOAD-BEARING. The refusal comment ALSO
# enumerates the commit range it would have reviewed, and on the PR that merged unreviewed
# that range's head equalled the PR head exactly. "The artifact names the current head" is
# therefore TRUE OF THE REFUSAL. So: classify against the refusal tables FIRST, and
# consider clearance only for what survives. `tests/review-clearance.test.sh` drives that
# exact false positive against the recorded comment body.
#
# THE THREE ROUTES TO EXIT 0, AND THERE ARE NO OTHERS
#
#   A. a REVIEW OBJECT whose `state` is exactly `APPROVED`, `CHANGES_REQUESTED` or
#      `COMMENTED` — compared case-sensitively against the API's own spellings, because
#      `pending`/`dismissed` in another casing used to slip past a case-sensitive skip
#      list — and whose `commit_id` equals the head. Evidence and pin both structural.
#      WITH ONE CORRECTION THE PIN ITSELF FORCED: a review object that says NOTHING is not
#      evidence on its own. `COMMENTED` is not a claim (the host mints one for any inline
#      comment or thread reply), so an empty one evidences nothing at all; an empty
#      `APPROVED`/`CHANGES_REQUESTED` is a claim, but neither may outrank a refusal
#      published at the same head. The old body-SHA pin refused those cases as a side
#      effect of being wrong; see the note at TEST 2.
#   B. a validated `okf-verdict` trailer whose `head_sha` equals the head, from an account
#      named with `--reviewer` that is NOT a vendor in REVIEWERS (see the tier-4 note).
#   C. a COMMENT carrying the reviewer's own MACHINE-EMITTED review marker
#      (REVIEW_SENTINEL) and naming the head. It exists because the reviewer this was
#      written against publishes a CLEAN review — "no actionable comments" — as an issue
#      comment and files no review object at all: four of the five reviews that clear the
#      35 pull requests here are that shape, so dropping the route would not make the gate
#      stricter, it would make it structurally unable to say yes to a clean review. It is
#      the weakest and the narrowest: an HTML comment the vendor's own renderer emits, in
#      a body whose fenced AND indented code blocks are gone. Prose cannot reach the
#      EVIDENCE half. ITS PIN IS THE RESIDUAL, AND IT IS STATED RATHER THAN GLOSSED: the
#      head named as a bare token in that body is the only pin an issue comment has —
#      there is no `commit_id` on a comment anywhere in the API — so route C alone still
#      rests on what a body happens to mention, which is the property THE TRAP below gives
#      the refusal too. What makes it survivable is that the pin cannot act alone: the
#      refusal tiers run first, and the machine marker must be there as well.
#
# THE TABLES CAN NO LONGER CAUSE A CLEARANCE. Every vendor string lives in REVIEWERS
# (whose artifacts count, and what its check is called), REFUSALS_SENTINEL / NOT_YET /
# REFUSALS ("I did not review") and REVIEW_SENTINEL (the vendor's own review marker). A
# missing or wrong row in any of them costs a REFUSAL: an unknown account is ignored, an
# unmatched refusal phrasing still has to get past A/B/C, an unmatched review marker lands
# on exit 4. REVIEWERS column 1 is EXACT logins, because `greptile.*` matched
# `greptile-evil` too. AND A CHECK NAME NEVER SETTLES ANYTHING, HERE OR IN THE CALLER:
# `--match-check`'s third answer — "looks like a reviewer's, and no row owns it" — rested
# on a table of vendor names and review phrasings, and that table was round four's route 1
# (a required check called `Codex Review`, or bare `Cursor`/`Copilot`/`Devin`/`PR Agent`,
# answered "plain CI" and settled green with zero artifacts read — the original incident
# with a 2026 vendor's name on it). It is DELETED rather than extended, because
# `required-checks.sh` now asks for clearance on every PR whatever its checks are called.
# `--match-check` keeps two answers and one job: which vendor owns a check, so one
# vendor's review cannot clear another's.
#
# A TABLE THAT DOES NOT COMPILE IS A TABLE THAT MATCHES NOTHING, which for the refusal
# tables means a refusal reads as a review. One typo'd ERE used to disable a whole table
# in silence, because the matcher read grep's OUTPUT and never its STATUS (1 is "no match",
# 2 is "your pattern is broken", and they are not the same answer). Every row of every
# table is now compiled up front by `validate_tables`, and every match checks grep's exit
# status — both refuse rather than proceeding with a table that cannot fire.
#
# WHAT THIS DOES NOT DO. It answers "did a review happen at this head", not "was the
# verdict good". Verdict adjudication is `SCHEMA.md` → "Independent verification gate"
# (the nine-clause predicate). A clean bill of health here means only that the reviewer
# looked; every other clause still applies.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It takes no org, repo or reviewer identity: those come from the arguments.
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  a review artifact from the reviewer EVIDENCES a completed review of the current
#      head, by route A, B or C above
#   1  the reviewer REFUSED to review (rate limit, quota, skip), or published only a
#      not-yet-reviewed placeholder. Quoted on stderr, with the reopen time when the
#      reviewer published one
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, unreadable PR or
#      review list, the PR's own author named as its reviewer, a pattern table that will
#      not compile) — an unknown state, never clearance
#   3  no reviewer signal at all: nothing on this PR from a known reviewer
#   4  an artifact exists but does not evidence a completed review OF THE CURRENT HEAD —
#      a review object made at an earlier commit, an artifact carrying no evidence a
#      review happened at all, or a `--head` that no longer matches the PR
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The quoted refusal comes from a PR comment, which
# anyone able to comment can write. It is quoted for a human to read and is never an
# input to the decision — the decision is the exit code. Do not parse the quote.
#
# FAILS CLOSED. Unknown, unreadable, unpinnable and unrecognised all refuse — including a
# truncated artifact fetch, which loses a review and lands on exit 3 rather than on a
# pass. A review this script cannot see is a review that did not happen.
#
# AND A TRUNCATED COPY OF THIS FILE IS UNKNOWN STATE TOO. `--self-test` proved this file
# RUNS, which is not proving it is COMPLETE: a copy cut off after the self-test block
# still runs, still prints the sentinel, and then classifies with half its tables — swept
# over an earlier version, 112 of its truncation points passed the old self-test and 109
# of those went on to clear an unreviewed PR. So the last line of this file is a
# completeness sentinel and the self-test asserts it, which no cut short of the end can
# satisfy.
#
# EXIT 4 IS THE COMMON ANSWER, NOT AN EXOTIC ONE, wherever the reviewer does not
# re-review every push. Measured over the 35 pull requests on the repository this was
# written in: 18 review objects exist across them, and exactly ONE was made by the
# reviewer at its PR's final head, because `.coderabbit.yaml` here sets
# `auto_incremental_review: false` — the agent pushes fixes after the review and nothing
# re-reads them. Those are stale reviews, not absent ones, and clause 3 of SCHEMA.md's
# predicate says stale is not cleared. Wiring this into a merge gate therefore means most
# PRs need a review requested at the FINAL head: a real operating cost, and the correct
# answer rather than a bug to tune out.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such assignment would exit the script with a success-looking code. Every
# failure path below is therefore explicit.
set -uo pipefail

# --- table 1: who is a reviewer, and what its check is called ----------------
# Two whitespace-separated fields per row, so neither may contain a space:
#
#   1. the account login that publishes the artifacts — an EXACT login, case-folded,
#      after a trailing "[bot]" is stripped. No wildcards, deliberately: `greptile.*` and
#      `(qodo|codium).*` were matched whole-string but ended in `.*`, so `greptile-evil`,
#      `qodo-attacker` and `codiumsquatter` all read as the vendor and any stranger who
#      could comment could clear a PR. A login spelled wrongly here is a login that is
#      IGNORED, which is exit 3 — the safe direction.
#   2. a POSIX ERE for the name its status check reports under (substring, case-folded)
#
# Column 2 is what `--match-check` answers on, and it exists to tell the caller which
# vendor owns a required check so that vendor's own artifacts answer for it. It never
# decides whether a review is needed — `required-checks.sh` asks on every PR.
#
# ONLY `coderabbitai` IS MEASURED HERE. The other five are each vendor's best-known bot
# login, taken from its documentation rather than from an artifact this script has seen —
# and a login spelled wrongly costs exit 3, so the risk of getting one wrong is a human
# glance. Confirm one against a real PR before relying on it, or name it with `--reviewer`.
#
# `--reviewer <login>` bypasses this table entirely, which is how a reviewer with no row
# yet — or the `qa-reviewer` fallback, posting under a human account — is named.
REVIEWERS='
coderabbitai            coderabbit
sourcery-ai             sourcery
greptile-apps           greptile
qodo-merge-pro          (qodo|codium|pr-agent)
codiumai-pr-agent-pro   (qodo|codium|pr-agent)
ellipsis-dev            ellipsis
'

# --- table 2a: the reviewer's own machine-readable "I did not review" sentinel -
# One POSIX ERE per line, matched case-insensitively against an artifact body whose
# fenced code blocks have been removed (see strip_fences). Blank lines and whole-line
# `#` comments are ignored; a pattern may not carry a trailing comment, because the
# whole line is the pattern. Same reading rules for every table below.
#
# THIS TIER IS UNCONDITIONAL and nothing outranks it but table 4. Hosted reviewers stamp
# their own automated notices with an HTML sentinel — a machine-readable claim, by the
# reviewer, sitting in the comment body. Measured over every pull request on this
# repository: the sentinel appears on exactly the rate-limit notices and on no review.
# The second row is the same claim in the generic HTML-marker shape other vendors use, so
# this tier is not one vendor's spelling.
REFUSALS_SENTINEL='
rate.limited by [a-z0-9._-]+
<!--[^>]*(rate|usage|quota)[^a-z0-9]?limit(ed|s)?[^>]*-->
'

# --- table 2c: "I have not reviewed it YET" -----------------------------------
# The reviewer posts a placeholder the moment the PR opens — "Currently processing new
# changes in this PR", quoting the head it is about to look at — and edits that same
# comment into the review when it finishes. It is on essentially every pull request, and
# it is the exact shape a default-allow classifier clears: an artifact, from the reviewer,
# naming the head, saying nothing that reads as a refusal. It is not a refusal. It is not
# a review either, and this file's job is to say so.
#
# UNCONDITIONAL, like the sentinel and for the same reason: "I am still working" is a
# claim about COMPLETION, and a marker elsewhere in the same body does not refute it.
#
# NARROW ON PURPOSE, unlike table 2b. An over-broad row here mislabels a real review as
# unfinished, and nothing outranks this tier, so each row names a placeholder phrasing
# rather than any sentence about reviewing. The refusal fixture's "keep reviewing this
# public repository" is why the `(is|are|am)` anchors are not optional.
NOT_YET='
currently (processing|reviewing|analy(s|z)ing)
review (is )?in progress
(is|are|am) (still )?(processing|reviewing) (the|your|new|this)
(have|has|had) not (yet )?(been )?review(ed)?
review (is |was |has |had )?not (yet )?(been )?(started|complete|completed|finished)
queued for review
'

# --- table 2b: the human-visible language of "I did not review" ---------------
# Deliberately over-broad, because a false refusal costs a human glance while a missed
# refusal costs an unreviewed merge — but over-broad prose matched against a whole
# comment body is ALSO how a real review gets called a refusal, so this tier is
# outranked by table 3. See the note there; the split is measured, not stylistic.
REFUSALS='
# the human-visible headings, verbatim from the PRs this script was written for
review limit reached
next included review available
# generic quota/limit phrasings across hosted reviewers
(rate|usage|plan|api) limit (reached|exceeded|hit)
(quota|credits) (exceeded|exhausted|reached|depleted|used up)
(daily|hourly|monthly|weekly) (review )?limit
no (reviews?|credits) (left|remaining)
used all (of )?(your |the )?(free |included )?(oss )?reviews
# generic "I chose not to look" phrasings
reviews? (was |were |is |are |has been |have been )?(skipped|not performed|not run)
skipping (this |the )?review
review (skipped|declined|deferred|postponed)
unable to (complete|perform|run) (the |this )?review
'

# --- table 3: the reviewer's own MACHINE-EMITTED review marker ----------------
# A row here outranks table 2b — never table 2a — and it is the evidence half of route C.
#
# WHY IT OUTRANKS 2b. A reviewer's REVIEW comment routinely carries a notice about
# something it did NOT do, and table 2b reads the whole body: "## Review skipped / Auto
# incremental reviews are disabled" sits at the top of the same comment that carries the
# walkthrough of a review that DID happen — on half of this repository's reviewed PRs,
# because `.coderabbit.yaml` here sets `auto_incremental_review: false` on purpose.
#
# EVERY ROW IS AN HTML COMMENT THE VENDOR'S RENDERER EMITS, and that is the design. This
# table used to hold PROSE — `i (have )?reviewed`, `(lgtm|looks good to me)`,
# `(changes requested|requesting changes)` — matched as unanchored substrings, the exact
# defect this file had already fixed for the verdict trailer: quoted approvals cleared,
# negated sentences like "Unreviewed <sha>" and "No changes requested" matched, and a
# prose quota refusal carrying one such phrase outranked the refusal tier. Prose is gone.
# What is left is the same CLASS of signal as REFUSALS_SENTINEL — a machine-readable claim
# by the reviewer, invisible in the rendered page, matched as a whole `<!-- ... -->`
# construct — ranked against it rather than against prose.
#
# WHAT THAT DID AND DID NOT MAKE SYMMETRIC, corrected from an earlier claim that all six
# vendors now get the same answer. What IS the same for all six: no vendor's prose clears
# anything, and refusal prose is only ever rescued by a MARKER. What is NOT: every row
# below is one vendor's spelling, and this table is not scoped to the vendor that posted
# the body — so the other five have no marker of their own to be rescued by (their real
# reviews reach exit 0 through a review object instead), while a body from any of them that
# QUOTES a row below is rescued by a marker its author does not emit. The unconditional
# tier above is the half that is genuinely vendor-neutral, through its second row.
#
# A MISSING ROW COSTS A REFUSAL: a vendor whose marker is not here files review objects or
# lands on exit 4, and `--reviewer` names it explicitly. A row that is too loose costs a
# CLEARANCE, so nothing belongs here that a placeholder or a banner could carry — which is
# why `review_stack_entry_start` was REMOVED rather than kept for symmetry with the other
# three. It wraps a "Review Change Stack" image and a `utm_campaign` link: a promotional
# banner the vendor emits around a review rather than evidence that one happened, and
# exactly what the sentence before this one excludes. Measured over all 35 pull requests
# here, removing it changes 0 outcomes; the fixture that carries it carries three real
# markers as well.
REVIEW_SENTINEL='
<!--[[:space:]]*walkthrough_start[[:space:]]*-->
<!--[[:space:]]*recent_review_start[[:space:]]*-->
<!--[[:space:]]*final_review_risk_start[[:space:]]*-->
'

# --- tier 4: an artifact that declares itself a review, structurally ----------
# The `okf-verdict` trailer (`SCHEMA.md` → "A verdict is a structured claim, not prose")
# is the fallback reviewer's own machine-readable output, and it outranks EVERY refusal
# row — including the sentinel. Not a convenience: a `qa-reviewer` verdict on a
# rate-limited PR has to SAY the hosted reviewer refused, quoting the words and the
# sentinel, which classifies the verdict itself as a refusal. That happened to the verdict
# on the PR that introduced this script.
#
# SO IT IS PARSED, NOT GREPPED. As one row of substrings, the highest-ranking tier here
# was a nineteen-character string: one appended `<!-- okf-verdict v1 -->` line turned the
# recorded rate-limit refusal from exit 1 into exit 0, and "no hosted reviewer emits that
# string" is untrue of a reviewer QUOTING A DIFF that contains it — this file ships it.
# `verdict_trailer` requires a well-formed block: the marker alone on its line, `-->`
# closing it, and the three fields SCHEMA.md's predicate needs, one of which is a
# `head_sha` equal to the head being cleared.
#
# AND THE TEXT IT PARSES IS THE STRICT RENDERING (see strict_body). Three doors reopened
# the bypass by feeding a sound parser unsound text: an INDENTED code block was never
# stripped, so a trailer GitHub renders as literal text validated as markup; a trailer
# NESTED in an outer HTML comment validated while GitHub renders the whole thing blank;
# and an unbalanced fence handed back the raw body, safe only while that body fed refusal
# detection. The strict rendering removes indented blocks as well as fenced ones and is
# EMPTY when the fences do not balance. The parser additionally discards a block
# containing a nested `<!--`, and one nobody closed, so state cannot leak between blocks.
#
# IT IS ALSO SCOPED, AND NOT BY `--reviewer` ALONE: honoured only for an account named
# with `--reviewer` that is NOT a vendor in REVIEWERS. Naming the vendor's own login used
# to re-arm the tier against that vendor's own refusal sentinel — and that vendor is
# precisely the account whose comments quote diffs.
VERDICT_MARKER='^[[:space:]]*<!--[[:space:]]*okf-verdict[[:space:]]+v[0-9]+[[:space:]]*$'

# The three review states GitHub's API publishes for a SUBMITTED review. Compared
# case-sensitively against the API's own spellings: the old skip list named `DISMISSED`
# and `PENDING` in a case-sensitive `case`, so a `pending` or `dismissed` in any other
# casing fell straight through it and was then treated as evidence.
SUBMITTED_STATES="APPROVED CHANGES_REQUESTED COMMENTED"

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  echo "                       [--reviewer <login>] [--for-check <check-name>]" >&2
  echo "       $(basename "$0") --match-check <check-name>   (0 a reviewer's, 1 not)" >&2
  echo "       $(basename "$0") --self-test                  (prove this script RUNS)" >&2
  exit 2
}

# --- table lookups (no network, no PR) ---------------------------------------
# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

fold() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# A login as every comparison here wants it: case-folded, with the host's "[bot]" suffix
# removed. `coderabbitai` and `coderabbitai[bot]` are one account, and the API returns
# both spellings depending on which endpoint answered.
norm() { fold "${1%\[bot\]}"; }

# hits <table> <file> — the matching lines of <file>, at most three, or nothing.
#
# GREP'S STATUS IS PART OF THE ANSWER, and ignoring it is how one typo disabled a whole
# table in silence: 1 means "no line matched" and 2 means "this pattern is not a regular
# expression", and reading only the (empty) OUTPUT turns the second into the first. For
# the refusal tables that reads a refusal as a review. Status 2 records the offending rows
# and returns 2; `fatal_grep` turns that into exit 2 in the caller, because this function
# runs inside a command substitution and cannot exit the script itself.
hits() {
  rows "$1" > "$TMPD/pat"
  grep -Ei -f "$TMPD/pat" "$2" > "$TMPD/hit" 2>/dev/null
  case "$?" in
    0) head -3 "$TMPD/hit"; return 0 ;;
    1) return 1 ;;
  esac
  local r rst
  while IFS= read -r r; do
    printf '' | grep -Eq "$r" 2>/dev/null; rst=$?
    [ "$rst" -le 1 ] || printf '%s\n' "$r" >> "$TMPD/grep-fatal"
  done < "$TMPD/pat"
  [ -s "$TMPD/grep-fatal" ] || printf '(a row this script could not isolate)\n' >> "$TMPD/grep-fatal"
  return 2
}

# Turn a hits() status-2 into a refusal. Called after each group of hits() calls.
fatal_grep() {
  [ -s "$TMPD/grep-fatal" ] || return 0
  echo "error: a pattern table in this script is not a valid POSIX ERE, so the table" >&2
  echo "       holding it matches nothing and the classification it drives is silently" >&2
  echo "       disabled. Refusing (fail closed). Offending row(s):" >&2
  sort -u "$TMPD/grep-fatal" | sed 's/^/          /' >&2
  exit 2
}

# Every pattern in every table, as one row per line — the argument to validate_tables,
# and the reason a two-column table is split before it is compiled.
all_patterns() {
  rows "$REVIEWERS" | awk '{print $1; print $2}'
  rows "$REFUSALS_SENTINEL"; rows "$NOT_YET"
  rows "$REFUSALS";          rows "$REVIEW_SENTINEL"
}

# Compile every row before anything is classified with it. A table that will not compile
# is not a table that matches less — it is a table that matches NOTHING, and a refusal
# table that matches nothing turns every refusal into a review. Checked here (up front, so
# the whole file is known good before one artifact is read), in --self-test (so the caller
# refuses a sibling carrying a broken table), and again at every match through hits().
validate_tables() {
  local bad="" r rst
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '' | grep -Eq "$r" 2>/dev/null; rst=$?
    [ "$rst" -le 1 ] || bad="$bad          $r
"
  done <<EOF
$(all_patterns)
EOF
  [ -n "$bad" ] || return 0
  echo "error: these rows in this script's pattern tables are not valid POSIX EREs, so" >&2
  echo "       the tables holding them match nothing and every decision they drive is" >&2
  echo "       silently disabled. Refusing (fail closed):" >&2
  printf '%s' "$bad" >&2
  return 2
}

# The col-1 login of every REVIEWERS row whose col-2 check pattern matches <check-name>.
# Empty when no row owns that check. Substring match, case-folded.
owners_of_check() {
  local needle; needle="$(fold "$1")"
  local row login check
  while IFS= read -r row; do
    # Fields via awk, never `set -- $row`: word-splitting a row would also pathname-expand
    # its column-2 ERE against the caller's cwd.
    login="$(printf '%s' "$row" | awk '{print $1}')"
    check="$(printf '%s' "$row" | awk '{print $2}')"
    [ -n "$login" ] && [ -n "$check" ] || continue
    printf '%s' "$needle" | grep -Eq "$check" 2>/dev/null && printf '%s\n' "$login"
  done <<EOF
$(rows "$REVIEWERS")
EOF
}

# Is <check-name> a reviewer's own status check?
#   0  yes, a table-1 row owns it (and owners_of_check names whose)
#   1  no row owns it
# There is no third answer any more, and no table of names that merely LOOK like a
# reviewer's: see the header. The caller does not use this to decide whether a review is
# required — only to decide whose artifacts answer for a given check.
match_check() { [ -n "$(owners_of_check "$1")" ]; }

# Does <login> match any of <newline-separated login patterns>? Whole-string,
# case-folded, "[bot]" stripped — the form every login test here takes.
match_patterns() {
  local login; login="$(norm "$1")"
  local pat
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$login" | grep -Eqx "$pat" 2>/dev/null && return 0
  done <<EOF
$2
EOF
  return 1
}

# Is <login> a known reviewer account at all?
match_reviewer() {
  match_patterns "$1" "$(rows "$REVIEWERS" | awk '{print $1}')"
}

# --- the two table-only modes: no network, no PR ------------------------------
#
# --self-test PROVES THIS SCRIPT RUNS, which `[ -x ]` does not. A caller whose whole job
# is to fail closed cannot ask the filesystem whether this file works: a dead shebang, a
# syntax error, a zero-byte file and a copy truncated half-way through an install all
# carry the executable bit and then fail every invocation, which used to read as "no
# required check is a reviewer's" and clear an unreviewed PR. So `required-checks.sh` runs
# this first and refuses unless it exits 0 AND prints SELFTEST_OK verbatim — that string
# is the contract between the two files, duplicated there on purpose (a shared constant
# would have to be sourced, and sourcing a broken file is the failure being tested for).
#
# THE CONTROLS ARE THE POINT: a banner would pass for any stub that prints a banner. This
# drives the table lookup the caller depends on in both directions, then classifies two
# literal bodies through the real refusal and review tables.
#
# AND "IT RUNS" IS NOT "IT IS COMPLETE" — the hole this block had. It sits near the TOP of
# the file, so a copy truncated anywhere BELOW it still parses, still reaches this exit and
# still prints the sentinel while the tables and the classifier it just vouched for are
# gone; 112 truncation points passed the old self-test and 109 then cleared an unreviewed
# PR. The last line of the file is therefore a sentinel, asserted here.
SELFTEST_OK="review-clearance: self-test ok"
EOF_SENTINEL="#EOF: review-clearance.sh is complete to here"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  [ -r "$0" ] || {
    echo "self-test: cannot read '$0' to prove it is complete — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so it is" >&2
    echo "           truncated or was cut short — the tables and the classifier below" >&2
    echo "           this line cannot be assumed to be here. Refusing." >&2; exit 2; }
  TMPD="$(mktemp -d)" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT
  validate_tables || exit 2
  match_check "CodeRabbit" || {
    echo "self-test: the reviewer table no longer matches its own canary" >&2; exit 2; }
  if match_check "Build, Lint & Format"; then
    echo "self-test: the reviewer table matches a plain CI job" >&2; exit 2
  fi
  # The classifier's own two directions, driven through the tables rather than described:
  # a refusal must be found in a refusal body, and the review marker in a reviewed one.
  printf 'Review limit reached.\n' > "$TMPD/probe"
  [ -n "$(hits "$REFUSALS" "$TMPD/probe")" ] || {
    echo "self-test: the refusal table does not match a refusal" >&2; exit 2; }
  printf '<!-- walkthrough_start -->\n' > "$TMPD/probe"
  [ -n "$(hits "$REVIEW_SENTINEL" "$TMPD/probe")" ] || {
    echo "self-test: the review-marker table does not match a review" >&2; exit 2; }
  [ -s "$TMPD/grep-fatal" ] && exit 2
  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

pr=""; repo=""; want_head=""; want_reviewer=""; for_check=""
if [ "${1:-}" = "--match-check" ]; then
  [ -n "${2:-}" ] && [ "$#" -eq 2 ] || usage
  # A table that will not compile answers "not a reviewer's check" to every name, which
  # would silently unscope the caller's clearance calls.
  validate_tables || exit 2
  match_check "$2"; exit $?
fi

# --- argument parsing --------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)     repo="${2:-}";           [ -n "$repo" ] || usage; shift 2 ;;
    --head)     want_head="${2:-}";      [ -n "$want_head" ] || usage; shift 2 ;;
    --reviewer) want_reviewer="${2:-}";  [ -n "$want_reviewer" ] || usage; shift 2 ;;
    --for-check) for_check="${2:-}";     [ -n "$for_check" ] || usage; shift 2 ;;
    -h|--help)  usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

# --- --for-check: whose review clears THIS required check ---------------------
# Without it, "a review exists on this PR" is asked of every reviewer at once, so on a
# repo with two of them one vendor's review clears the other vendor's required check
# while that vendor was rate-limited. The check name resolves to the REVIEWERS rows that
# own it, and only those logins are considered below. A name no row owns is not a
# question this script can answer — it refuses rather than widening to everybody.
check_owners=""
if [ -n "$for_check" ]; then
  check_owners="$(owners_of_check "$for_check")"
  [ -n "$check_owners" ] || {
    echo "error: no reviewer in this script's table owns the check '$for_check', so" >&2
    echo "       whose review would clear it is unknown. Refusing (fail closed). Add a" >&2
    echo "       row to REVIEWERS, or name the account with --reviewer <login>." >&2
    exit 2
  }
  [ -n "$want_reviewer" ] && {
    echo "error: --for-check and --reviewer both name whose review counts; pass one." >&2
    exit 2
  }
fi

# The verdict trailer is honoured only for an explicitly named NON-VENDOR account. See
# the tier-4 note: `--reviewer coderabbitai` used to re-arm the highest tier in the file
# against that vendor's own machine-readable refusal.
trailer_armed=""
if [ -n "$want_reviewer" ] && ! match_reviewer "$want_reviewer"; then trailer_armed=yes; fi

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found — cannot read reviewer state, so this refuses" >&2
    exit 2
  }
done

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# Before a single artifact is read: every row of every table has to compile. See
# validate_tables — a broken refusal row reads a refusal as a review.
validate_tables || exit 2

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- the PR, and then the reviews ---------------------------------------------
# `gh pr view` answers the PR's facts and its ISSUE comments. It does NOT expose a
# review's `commit_id`, which is the whole reason this file used to pin a review by
# whether its body happened to mention the head SHA — the property the REFUSAL also has.
# `/repos/{owner}/{repo}/pulls/{n}/reviews` does expose it, alongside the review's
# `state`, so the second call below is what makes routes A and B structural.
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,number,headRefOid,author,comments 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — refusing (fail closed)" >&2
  exit 2
}

meta="$(printf '%s' "$raw" \
        | jq -r '[.url, .headRefOid, (.author.login // ""), (.number // "" | tostring)] | @tsv' \
          2>/dev/null)" || meta=""
url="$(printf '%s' "$meta" | cut -f1)"
head_sha="$(printf '%s' "$meta" | cut -f2)"
pr_author="$(printf '%s' "$meta" | cut -f3)"
pr_number="$(printf '%s' "$meta" | cut -f4)"
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"
[ -n "$url" ] && [ -n "$head_sha" ] && [ -n "$pr_number" ] && [ "$nwo" != "$url" ] || {
  echo "error: could not resolve the head SHA / repo of PR $pr — refusing (fail closed)" >&2
  exit 2
}

# AND THE AUTHOR LOGIN IS PART OF THAT GUARD, because a field that is missing here does
# not fail — it silently switches off a rule. SCHEMA.md clause 8 (an author is never its
# own independent reviewer) is enforced below by comparing logins against `$pr_author`, so
# an absent or empty one turns both comparisons into a test against the empty string,
# which nothing equals: the reviewer account then clears its own pull request, and the two
# `continue`s that exist to stop it never fire. Every PR has an author, so no author means
# the read did not answer — unknown state, and unknown fails closed.
[ -n "$pr_author" ] || {
  echo "error: PR $pr reports no author login, so the rule that an author is not its own" >&2
  echo "       independent reviewer (SCHEMA.md, clause 8) cannot be applied — and a rule" >&2
  echo "       that cannot be applied is not a rule that passes. Refusing (fail closed)." >&2
  exit 2
}

# A review list this script cannot read is an unknown reviewer state, not an empty one:
# reading it as "no reviews" would turn a transient 5xx into "nothing reviewed this",
# which is a refusal today but would be a clearance the moment anything downstream
# treated exit 3 as benign. Refuse outright.
gh api "/repos/$nwo/pulls/$pr_number/reviews?per_page=100" --paginate \
  --jq '.[] | {login: (.user.login // ""), state: (.state // ""),
               commit: (.commit_id // ""), body: (.body // "")}' \
  > "$TMPD/reviews.ndjson" 2>/dev/null || {
  echo "error: could not read the review objects on PR $pr ($nwo) — refusing." >&2
  echo "       Whether anybody reviewed this head is unknown, and unknown fails closed." >&2
  exit 2
}

# The verified head the caller pinned must still be the PR's head; if it is not, every
# answer below is about a different commit. Same rule as required-checks.sh, reported as
# staleness because that is what it is.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "refuse: head moved — verified $want_head, PR $pr is now at $head_sha" >&2
  exit 4
fi

# The implementing author is never its own independent reviewer (SCHEMA.md, clause 8).
if [ -n "$want_reviewer" ] && [ "$(norm "$want_reviewer")" = "$(norm "$pr_author")" ]; then
  echo "error: --reviewer $want_reviewer is the author of PR $pr — an author cannot be" >&2
  echo "       its own independent reviewer. Refusing." >&2
  exit 2
fi

# --- split the artifacts into files ------------------------------------------
# Bodies are multi-line markdown, so they cannot travel as TSV fields. jq emits a header
# line then the raw body; awk cuts on the header.
#
# THE SEPARATOR IS RANDOM PER RUN, and that is a security property rather than a style.
# Artifact bodies are attacker-writable — anyone who can comment on a PR can write
# anything into one — so a fixed sentinel could be typed into a comment to forge a record
# boundary and fabricate an artifact with an author, a state and a commit_id of the
# forger's choosing. Sixteen random bytes cannot be guessed by the text being parsed. The
# length is asserted EXACTLY (4 + 32 hex digits): a `>` test passes on a separator with
# six bytes of entropy in it, which is guessable.
SEP="okf-$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
[ "${#SEP}" -eq 36 ] || {
  echo "error: could not generate a record separator — refusing (fail closed)" >&2
  exit 2
}

printf '%s' "$raw" | jq -r --arg s "$SEP" --slurpfile rv "$TMPD/reviews.ndjson" '
    ( ($rv[]         | {kind:"review",  login:(.login // ""), state:(.state // ""),
                        commit:(.commit // ""), body:(.body // "")}),
      (.comments[]?  | {kind:"comment", login:(.author.login // ""), state:"",
                        commit:"",              body:(.body // "")}) )
    | "\($s)\t\(.kind)\t\(.login)\t\(.state)\t\(.commit)", .body
  ' 2>/dev/null > "$TMPD/stream" || {
  echo "error: could not parse the artifacts on PR $pr — refusing (fail closed)" >&2
  exit 2
}

: > "$TMPD/index"
awk -v s="$SEP" -v dir="$TMPD" '
  substr($0, 1, length(s) + 1) == s "\t" {
    if (f) close(f)
    n++
    print substr($0, length(s) + 2) >> (dir "/index")
    f = dir "/body." n
    printf "" > f
    next
  }
  f { print >> f }
' "$TMPD/stream"

# --- what a FENCE is: ONE rule, shared by both renderings below ---------------
#
# THE TWO RENDERINGS HAVE TO AGREE ABOUT THIS, AND THEY DID NOT. `strip_fences` stripped
# any leading whitespace before testing for a fence, while `strict_body` treated a line
# indented four spaces (or a tab) as an INDENTED CODE BLOCK and therefore not a fence. So
# an indented ``` opened a fence on the REFUSAL side and opened nothing on the CLEARING
# side: the unconditional refusal sentinel sitting between two such markers vanished from
# the text the refusal tables read, while a review marker outside them survived on the side
# that clears. A verbatim recorded refusal cleared at exit 0 — a fourth door into the same
# bypass, and the INVERSE of the asymmetry this file states about itself below, since the
# strict rendering was keeping lines the stripped one had already removed.
#
# THE RULE FOLLOWS THE HOST'S RENDERING, because both renderings are guesses about what a
# human sees. A fence may be indented at most three spaces and may sit inside blockquote
# markers (each itself indented at most three); four spaces or one tab makes the line
# LITERAL TEXT, and the host then renders ``` as three backticks rather than opening a
# block. Which way each mistake fails is the whole point: text the host renders as TEXT
# must reach the refusal tables, and calling that a fence hides a refusal a human can
# plainly read. Text the host renders as CODE is a quotation, and a quoted refusal has
# always been read here as a discussion of one rather than as one (the fenced-refusal case
# in the tests) — that part is deliberate, tested, and unchanged.
FENCE_AWK='
function bq_peel(s) {                 # strip blockquote markers, each <=3 spaces indented
  while (match(s, /^ ? ? ?>[ ]?/)) s = substr(s, RLENGTH + 1)
  return s
}
function indented_of(line,   s) {     # 1 when the host renders this line as literal code
  s = bq_peel(line)
  if (s ~ /^\t/) return 1
  # Leading spaces measured rather than matched with an interval expression: `{0,3}` is
  # not portable across every awk this template may run under.
  match(s, /^ */)
  return (RLENGTH >= 4) ? 1 : 0
}
function fence_of(line,   s, n) {     # the fence marker this line opens or closes, or ""
  if (indented_of(line)) return ""
  s = bq_peel(line)
  match(s, /^ */); n = RLENGTH
  s = substr(s, n + 1)
  if (substr(s, 1, 3) == "```") return "```"
  if (substr(s, 1, 3) == "~~~") return "~~~"
  return ""
}
'

# --- two renderings of one body, and the asymmetry is deliberate --------------
#
# strip_fences() removes FENCED code blocks and is what the REFUSAL tables read. The
# opening marker's TYPE is carried, so ``` inside a ~~~ block is content rather than a
# close.
#
# UNBALANCED FENCES HAND BACK THE RAW BODY. A toggle with no END check is a one-character
# bypass: a single prepended ``` inverts it, every later line reads as "inside a fence",
# the stripped body comes back EMPTY and no refusal matches. So an odd count means "this
# body cannot be read as fenced markdown", and refusal language then counts wherever it
# sits — a human glance at worst, never a merge.
strip_fences() {
  awk "$FENCE_AWK"'
    { raw[NR] = $0
      marker = fence_of($0)
      if (marker != "" && (open == "" || open == marker)) {
        open = (open == "" ? marker : "")
        next
      }
      if (open == "") keep[++k] = $0
    }
    END {
      if (open != "") { for (i = 1; i <= NR; i++) print raw[i] }
      else            { for (i = 1; i <= k;  i++) print keep[i] }
    }
  ' "$1"
}

# strict_body() is what the CLEARING side reads — the review marker, the verdict trailer
# and the head token. It removes the same fenced blocks strip_fences removes, then
# INDENTED code blocks as well, and prints NOTHING when the fences do not balance.
#
# THE ASYMMETRY IS THE SAFETY PROPERTY, AND IT IS A CONTAINMENT: every line the strict
# rendering keeps is a line the stripped rendering kept too (strict is a SUBSET of
# stripped), never the other way round. Strip too much on the refusal side and a refusal
# disappears (fail open), so that side strips the minimum; strip too little on the clearing
# side and text the host renders as literal code is read as markup (fail open), so this
# side strips the maximum. That containment holds only while the two agree on what a fence
# is, which is why fence_of() above is ONE function rather than two spellings of an idea:
# it used to run backwards on an indented fence, and a refusal cleared through the gap.
strict_body() {
  awk "$FENCE_AWK"'
    { fence = fence_of($0)
      if (fence != "" && (open == "" || open == fence)) {
        open = (open == "" ? fence : "")
        next
      }
      if (open != "") next
      if (indented_of($0)) next        # an indented code block renders as literal text
      keep[++k] = $0
    }
    END {
      if (open != "") exit 0            # unbalanced: an unreadable body clears nothing
      for (i = 1; i <= k; i++) print keep[i]
    }
  ' "$1"
}

# Every prefix of the head from 7 chars up, so an artifact may name the commit in full or
# abbreviated. Compared against the hex tokens in the body, never against a range syntax:
# the range is exactly what the refusal also carries.
: > "$TMPD/prefixes"
i=7
while [ "$i" -le "${#head_sha}" ]; do
  printf '%s\n' "$(printf '%s' "$head_sha" | cut -c1-"$i")" >> "$TMPD/prefixes"
  i=$((i + 1))
done

# names_head <strict-body-file> — does this artifact name the current head as a token of
# its own? URLs are removed first: a SHA inside a link (a compare view, a commit
# permalink, an avatar hash) is not the artifact claiming to have read that commit, and it
# used to count. This is route C's pin ONLY — routes A and B pin on `commit_id` and on the
# trailer's `head_sha` field, never on what the body happens to mention.
names_head() {
  sed -E "s#https?://[^[:space:])\"']*##g" "$1" 2>/dev/null \
    | grep -Eo '[0-9a-fA-F]{7,40}' | tr '[:upper:]' '[:lower:]' > "$TMPD/toks"
  grep -qxF -f "$TMPD/prefixes" "$TMPD/toks"
}

# `hits` and `fatal_grep` are defined up with the tables, because --self-test drives them.

refusal_hits() { # <stripped-body-file> — the refusal lines, from any refusal tier
  { hits "$REFUSALS_SENTINEL" "$1"; hits "$NOT_YET" "$1"; hits "$REFUSALS" "$1"; } | head -3
}

# --- tier 4, parsed: is there a well-formed okf-verdict block for THIS head? ---
verdict_trailer() { # <strict-body-file>
  awk -v head="$head_sha" -v marker="$VERDICT_MARKER" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    {
      line = $0
      if (inblk) {
        if (line ~ /^[[:space:]]*-->[[:space:]]*$/) {
          inblk = 0
          if (verdict ~ /^(pass|changes-requested|inconclusive)$/ && reviewer != "" \
              && sha ~ /^[0-9a-f]{7,40}$/ && substr(head, 1, length(sha)) == sha) found = 1
          next
        }
        # A nested comment marker inside the block means this is not the flat, structured
        # trailer SCHEMA.md defines — discard it rather than carrying its fields onward.
        if (index(line, "<!--") > 0 || index(line, "-->") > 0) { inblk = 0; next }
        f = trim(line)
        if (f ~ /^[a-zA-Z_]+:/) {
          key = tolower(trim(substr(f, 1, index(f, ":") - 1)))
          val = tolower(trim(substr(f, index(f, ":") + 1)))
          if (key == "verdict")  verdict  = val
          if (key == "reviewer") reviewer = val
          if (key == "head_sha") sha      = val
        }
        next
      }
      # A trailer that opens INSIDE another HTML comment is rendered blank by the host and
      # is not a claim anybody can see — it is not a trailer.
      if (htmlopen == 0 && line ~ marker) {
        inblk = 1; verdict = ""; reviewer = ""; sha = ""; next
      }
      o = gsub(/<!--/, "&", line); c = gsub(/-->/, "&", line)
      htmlopen += o - c
      if (htmlopen < 0) htmlopen = 0
    }
    # A block nobody closed is not a block: dropping out of the loop inside one must not
    # leave its fields to be completed by the next one.
    END { exit(found ? 0 : 1) }
  ' "$1"
}

reopen_line() { # <stripped-body-file> — when the reviewer published a reopen time
  grep -Ei \
    -e 'next .{0,20}(review|run).{0,20}(available|in) ' \
    -e '(limit|quota|it) (will )?(reset|resets|resetting)' \
    -e 'try again (in|at|after) ' \
    -e 'available (again )?(in|at) ' \
    "$1" \
    | head -1 | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' -e 's/^[*#[:space:]]*//' \
                    -e 's/[*[:space:]]*$//'
}

n=0; considered=0; refusal_body=""; refusal_from=""; refusal_kind=""
stale_from=""; stale_at=""; unproven_from=""
refusal_at_head=""; empty_from=""; empty_state=""; held_from=""; held_state=""
while IFS=$'\t' read -r kind login state commit; do
  n=$((n + 1))
  body="$TMPD/body.$n"
  [ -f "$body" ] || : > "$body"
  [ -n "$login" ] || continue

  # Whose opinion counts, in three narrowing steps. --for-check restricts to the reviewer
  # that OWNS the required check being cleared, so one vendor's review cannot clear
  # another's; --reviewer names one account outright; with neither, the REVIEWERS table
  # decides. An account in none of them is ignored rather than trusted, so a teammate's
  # "lgtm" never stands in for the independent gate.
  if [ -n "$check_owners" ]; then
    match_patterns "$login" "$check_owners" || continue
  elif [ -n "$want_reviewer" ]; then
    [ "$(norm "$login")" = "$(norm "$want_reviewer")" ] || continue
  else
    match_reviewer "$login" || continue
  fi
  # An author's own artifact is never independent, whichever table matched.
  [ "$(norm "$login")" = "$(norm "$pr_author")" ] && continue

  # A review object is evidence only in one of the API's three SUBMITTED states, compared
  # against its own spellings. Anything else — PENDING, DISMISSED, a casing variant, a
  # state this script has never heard of — is not a submitted review and is skipped here
  # rather than being allowed to fall through into the evidence tests.
  submitted=""
  if [ "$kind" = "review" ]; then
    for s in $SUBMITTED_STATES; do [ "$state" = "$s" ] && submitted=yes; done
    [ -n "$submitted" ] || continue
  fi

  considered=$((considered + 1))
  strip_fences "$body" > "$TMPD/stripped"
  strict_body  "$body" > "$TMPD/strict"

  # TEST 1 — did this artifact DECLINE to review? FIRST, always, because the refusal names
  # the head too, and a detector that pins first reads a refusal as a review. Four tiers,
  # highest first (see the tables): a structured verdict from an explicitly named
  # non-vendor reviewer is a review whatever it quotes; a machine sentinel is a refusal
  # whatever else it carries; so is a not-yet-reviewed placeholder; refusal PROSE is a
  # refusal unless the reviewer's own machine-emitted review marker is in the same body.
  verdict=""
  if [ -n "$trailer_armed" ] && verdict_trailer "$TMPD/strict"; then verdict=yes; fi
  refusal=""; kind_of_refusal=""
  if [ -z "$verdict" ]; then
    if [ -n "$(hits "$REFUSALS_SENTINEL" "$TMPD/stripped")" ]; then
      refusal=yes; kind_of_refusal=declined
    elif [ -n "$(hits "$NOT_YET" "$TMPD/stripped")" ]; then
      refusal=yes; kind_of_refusal=unfinished
    elif [ -n "$(hits "$REFUSALS" "$TMPD/stripped")" ] \
      && [ -z "$(hits "$REVIEW_SENTINEL" "$TMPD/strict")" ]; then
      refusal=yes; kind_of_refusal=declined
    fi
  fi
  fatal_grep
  if [ -n "$refusal" ]; then
    # Does this refusal concern THE HEAD BEING CLEARED? Body text, deliberately, and only
    # in the CLOSING direction: a false positive here costs a human a glance at a PR that
    # was in fact reviewed, never a merge. It reads the wider (stripped) rendering for the
    # same reason. Nothing clears on this answer — it is consulted below only to stop a
    # CONTENTLESS review object from outranking a refusal published at the same commit.
    names_head "$TMPD/stripped" && refusal_at_head=yes
    [ -n "$refusal_body" ] || { refusal_body="$TMPD/refusal"; refusal_from="$login"
                                refusal_kind="$kind_of_refusal"
                                cp "$TMPD/stripped" "$TMPD/refusal"; }
    continue
  fi

  # TEST 2 — is this a review OF THIS COMMIT? The three routes of the header. Evidence and
  # pin travel together in each of them, and in A and B neither half is prose; route C's
  # pin is the one place a body-mentioned SHA still decides anything (see its note below).
  #
  #   B. the validated trailer, pinned by its own head_sha field
  #   A. a submitted review object, pinned by the API's commit_id
  #   C. the vendor's machine-emitted review marker, pinned by the head named in the
  #      strict rendering of the body
  if [ -n "$verdict" ]; then
    echo "ok: a validated okf-verdict trailer from $login ($kind) names head $head_sha on PR $pr"
    exit 0
  fi
  if [ "$kind" = "review" ]; then
    if [ -n "$commit" ] && [ "$commit" = "$head_sha" ]; then
      # A REVIEW OBJECT AT THE HEAD WITH NOTHING IN IT IS NOT AUTOMATICALLY A REVIEW, and
      # this is what moving the pin to `commit_id` gave away. The old body-SHA pin was
      # wrong for every reason the header lists, but in this ONE respect it failed closed:
      # an empty body cannot name a head, so an empty review object could not clear. Once
      # `state` + `commit_id` became the pin, an empty-bodied COMMENTED object at the head
      # cleared OVER the reviewer's own verbatim rate-limit refusal at that same head.
      #
      # `COMMENTED` is not a claim. The host mints one for any inline comment and any
      # thread reply — twelve empty-bodied COMMENTED objects already sit in this
      # repository's own corpus — so for that state the claim, if there is one, is in the
      # body. `APPROVED` and `CHANGES_REQUESTED` ARE claims whatever the body says: the
      # state IS the verdict, and an approval with no words is still an approval. Neither
      # kind, though, may outrank a refusal published at this same head, so a contentless
      # one is HELD and decided after every artifact has been read (see below) rather than
      # exiting here. A PR must still be able to recover from having been refused once,
      # which is why the refusal has to name this head to win rather than merely exist.
      if grep -q '[^[:space:]]' "$TMPD/strict" 2>/dev/null; then
        echo "ok: a submitted review ($state) from $login was made at head $head_sha on PR $pr"
        exit 0
      fi
      if [ "$state" = "COMMENTED" ]; then
        [ -n "$empty_from" ] || { empty_from="$login"; empty_state="$state"; }
        continue
      fi
      [ -n "$held_from" ] || { held_from="$login"; held_state="$state"; }
      continue
    fi
    # A review object that is not at this head is stale in the API's own terms — no text
    # is consulted, and no body-mentioned SHA can rescue it.
    [ -n "$stale_from" ] || { stale_from="$login ($kind, $state)"
                              stale_at="${commit:-an unrecorded commit}"; }
    continue
  fi
  if [ -n "$(hits "$REVIEW_SENTINEL" "$TMPD/strict")" ]; then
    fatal_grep
    if names_head "$TMPD/strict"; then
      echo "ok: $login's own review marker in a comment names head $head_sha on PR $pr"
      exit 0
    fi
    [ -n "$stale_from" ] || { stale_from="$login ($kind)"; stale_at="no commit it names"; }
    continue
  fi
  fatal_grep
  [ -n "$unproven_from" ] || unproven_from="$login ($kind)"
done < "$TMPD/index"

# --- the one clearance that could not be decided inside the loop --------------
#
# A CONTENTLESS `APPROVED` / `CHANGES_REQUESTED` OBJECT AT THE HEAD. The state is the
# verdict, so it clears — but only now, with every artifact read, and only if none of them
# refused THIS head. Deciding it inside the loop is what the defect was: review objects are
# streamed before comments, so an empty object short-circuited past a refusal that had not
# been looked at yet. An earlier refusal at some OTHER commit still loses to it, because a
# PR that was skipped once has to be able to recover.
if [ -n "$held_from" ] && [ -z "$refusal_at_head" ]; then
  echo "ok: a submitted review ($held_state) from $held_from was made at head $head_sha on PR $pr"
  exit 0
fi

# --- nothing cleared: say precisely which shape this PR is -------------------
#
# The quoted lines are UNTRUSTED TEXT from a PR comment (see the header). They are stripped
# of control characters before they reach a terminal, so a body cannot repaint the
# operator's screen or hide the rest of this message behind an escape sequence.
if [ -n "$refusal_body" ]; then
  if [ "$refusal_kind" = "unfinished" ]; then
    echo "refuse: $refusal_from has NOT FINISHED reviewing PR $pr — a placeholder is not a" >&2
    echo "        review, however green its status check is. It said:" >&2
  else
    echo "refuse: $refusal_from DECLINED to review PR $pr — this is not clearance, however" >&2
    echo "        green its status check is. It said:" >&2
  fi
  refusal_hits "$refusal_body" | tr -d '\000-\010\013-\037' \
                               | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' \
                                     -e 's/^[*#[:space:]]*//' -e 's/[*[:space:]]*$//' \
                                     -e 's/^/          | /' >&2
  when="$(reopen_line "$refusal_body" | tr -d '\000-\010\013-\037')"
  if [ -n "$when" ]; then
    echo "        Reopens: $when" >&2
  else
    echo "        No reopen time published — re-request a review once the quota resets." >&2
  fi
  echo "        A skipped PR is NOT re-reviewed automatically: nothing re-runs until a" >&2
  echo "        new commit lands or someone asks for a first review." >&2
  # Say so when a contentless review object sat at this same head, or the operator reads
  # "nobody reviewed it" while looking at a review object in the browser.
  contentless="${held_from:-$empty_from}"; contentless_state="${held_state:-$empty_state}"
  [ -n "$contentless" ] && {
    echo "        (A $contentless_state review object from $contentless sits at this same head" >&2
    echo "        with an EMPTY body. An empty review object does not outrank a refusal" >&2
    echo "        published at that commit — see the note at TEST 2.)" >&2
  }
  exit 1
fi

# A review object at the head that says nothing. Its own shape rather than "no evidence",
# because the operator can see it in the browser and needs to be told why it did not count.
if [ -n "$empty_from" ]; then
  echo "refuse: the review object on PR $pr from $empty_from is at head $head_sha but its" >&2
  echo "        body is EMPTY, and an empty $empty_state review is not a claim that anybody" >&2
  echo "        read anything: the host mints one for any inline comment or thread reply, so" >&2
  echo "        the claim, where there is one, is the body. Ask for a review at this head," >&2
  echo "        or look." >&2
  exit 4
fi

if [ -n "$stale_from" ]; then
  echo "refuse: the review on PR $pr is from $stale_from and was made at $stale_at," >&2
  echo "        not at head $head_sha. A verdict for a commit that is no longer the head" >&2
  echo "        is stale. This is the ORDINARY outcome where the reviewer does not" >&2
  echo "        re-review on every push (CodeRabbit's \`auto_incremental_review: false\`):" >&2
  echo "        the review is real and it is not of this commit. Ask for a review at this" >&2
  echo "        head, or look." >&2
  exit 4
fi

# An artifact from the reviewer that evidences no completed review. Its own shape, not
# folded into "no reviewer signal": something IS there, and saying "nothing on this PR"
# about a comment the operator can see in the browser gets this script disbelieved rather
# than the PR looked at. The placeholder the reviewer posts before it reads anything is
# the common case, and it used to clear.
if [ -n "$unproven_from" ]; then
  echo "refuse: the only artifact on PR $pr is from $unproven_from and carries no evidence" >&2
  echo "        that a review was COMPLETED — it is not a submitted review object at this" >&2
  echo "        head, it carries no verdict trailer, and it carries none of the reviewer's" >&2
  echo "        own review markers. A reviewer posting on a PR is not a reviewer having" >&2
  echo "        read it (the 'currently processing' placeholder is on nearly every PR)." >&2
  echo "        Ask for a review at this head, or look." >&2
  exit 4
fi

echo "no-review: nothing on PR $pr from a known reviewer${want_reviewer:+ ($want_reviewer)}${for_check:+ (owner of '$for_check')}." >&2
echo "        $n artifact(s) on the PR, $considered from a reviewer. An absent review is" >&2
echo "        NOT a pass — surface the PR for a human, or dispatch the fallback reviewer." >&2
[ -n "$want_reviewer" ] || echo "        Pass --reviewer <login> if this repo uses a reviewer with no table row." >&2
exit 3

# --- completeness sentinel — THIS MUST REMAIN THE LAST LINE OF THIS FILE ------
# `--self-test` asserts that the last line of this file is exactly the line below, which
# is the only cheap thing a file can say about itself that a TRUNCATED copy cannot. The
# self-test block sits hundreds of lines above, so "it runs" was true of copies missing
# every table under it; 112 truncation points passed it and 109 then cleared an unreviewed
# PR. Do not add anything after it, and do not restate it anywhere else in the file.
#EOF: review-clearance.sh is complete to here
