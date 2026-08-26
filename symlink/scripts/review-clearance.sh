#!/usr/bin/env bash
#
# review-clearance.sh — assert that an independent review ARTIFACT exists on a pull
# request, at its current head. This is precondition 2 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is precondition 1, and
# calls in here whenever one of the REQUIRED checks turns out to be a reviewer's own.
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
# So nothing here reads a check conclusion. It reads the reviewer's ARTIFACTS — review
# objects and issue comments — and asks whether any of them is a review.
#
# THE TRAP, AND WHY THE ORDER OF THE TWO TESTS BELOW IS LOAD-BEARING. The refusal comment
# ALSO enumerates the commit range it would have reviewed, and on the PR that merged
# unreviewed that range's head equalled the PR head exactly. "The artifact names the
# current head" is therefore TRUE OF THE REFUSAL, and any detector keying on that range
# reads a refusal as a review. Only the refusal LANGUAGE separates the two. Hence:
# classify against the refusal table FIRST, and pin only what survives to the head —
# never the other way round. `tests/review-clearance.test.sh` drives that exact false
# positive against the recorded comment body.
#
# PROVIDER-AGNOSTIC BY CONSTRUCTION. Every vendor-specific string lives in one of the
# tables below and nowhere else in this file: REVIEWERS (who counts as a reviewer, and
# what its status check is called), SUSPECT_CHECKS (check names that look like a
# reviewer's but match no row — unknown, so they refuse rather than settle), REFUSALS
# (the language of "I did not review") and REVIEWED (positive evidence that an artifact
# IS a review). Adopting a different reviewer is a row, not a rewrite. An unrecognised
# reviewer is not a pass — it is exit 3, which refuses — so the failure mode of a stale
# table is a human looking, never a merge.
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
#   0  a review artifact from the reviewer exists and names the current head
#   1  the reviewer REFUSED to review (rate limit, quota, skip). Quoted on stderr,
#      with the reopen time when the reviewer published one
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, unreadable PR,
#      the PR's own author named as its reviewer) — an unknown state, never clearance
#   3  no reviewer signal at all: nothing on this PR from a known reviewer
#   4  an artifact exists but is not tied to the CURRENT head — a stale review, one
#      that names no commit, or a `--head` that no longer matches the PR
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The quoted refusal comes from a PR comment, which
# anyone able to comment can write. It is quoted for a human to read and is never an
# input to the decision — the decision is the exit code. Do not parse the quote.
#
# FAILS CLOSED. Unknown, unreadable, unpinnable and unrecognised all refuse — including a
# truncated artifact fetch, which loses a review and lands on exit 3 rather than on a
# pass. A review this script cannot see is a review that did not happen. `--match-check`
# carries the same rule into the caller: 0 is a known reviewer's check, 1 is a CI job,
# and 3 is a check that LOOKS like a reviewer's while no table row owns it — unknown, so
# the caller must refuse rather than settle it on a green bucket.
#
# EXIT 4 IS THE COMMON ANSWER, NOT AN EXOTIC ONE, wherever the reviewer does not
# re-review every push. Measured over the 35 pull requests on the repository this was
# written in: 15 carry a review object and exactly ONE of them was made at the PR's final
# head, because `.coderabbit.yaml` here sets `auto_incremental_review: false` — the agent
# pushes fixes after the review and nothing re-reads them. Those are stale reviews, not
# absent ones, and clause 3 of SCHEMA.md's predicate says stale is not cleared. Wiring
# this into a merge gate therefore means most PRs need a review requested at the FINAL
# head; that is a real operating cost and it is the correct answer, not a bug to tune out.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such assignment would exit the script with a success-looking code. Every
# failure path below is therefore explicit.
set -uo pipefail

# --- table 1: who is a reviewer, and what its check is called ----------------
# Two whitespace-separated POSIX EREs per row, so neither field may contain a space:
#
#   1. the account login that publishes the artifacts (matched whole, case-folded,
#      after a trailing "[bot]" is stripped)
#   2. the name its status check reports under (matched as a substring, case-folded)
#
# Column 2 is what `--match-check` answers on, and it is the reason `required-checks.sh`
# can tell "this required check is a reviewer's opinion" from "this required check is
# CI". A repo that requires the reviewer's check has NOT thereby required a review.
#
# `--reviewer <login>` bypasses this table entirely, which is how a reviewer that has no
# row yet — or the `qa-reviewer` fallback, posting under a human account — is named.
REVIEWERS='
coderabbitai            coderabbit
sourcery-ai             sourcery
(qodo|codium).*         (qodo|codium|pr-agent)
greptile.*              greptile
ellipsis-dev            ellipsis
'

# --- table 1b: check names that LOOK like a reviewer's but match no row above --
# One POSIX ERE per line, matched as a substring against a case-folded check name.
#
# WHY THIS EXISTS. Table 1 answers "is this required check a known reviewer's". Its
# no-answer used to mean "then it is CI, settle it on its bucket" — which is the original
# incident with a different vendor's name on it: a repo requiring `Cursor Bugbot`,
# `Copilot code review` or `Devin Review` has a reviewer's green check in its required
# set, table 1 says "not mine", and the check clears on a bucket that is green whether or
# not anything was reviewed. UNKNOWN IS NOT CI. A name that matches here and nothing in
# table 1 makes `--match-check` exit 3, and the caller must refuse: the state of that
# reviewer is unreadable, and unreadable fails closed.
#
# Deliberately NOT a catch-all. `review` on its own is a CI job name (`Review Docs`,
# a Heroku `review-app` deploy), so only phrasings that name a CODE review, or a vendor
# whose product is one, belong here — the cost of a row is a repo that must rename a
# CI check, and the cost of a missing row is an unreviewed merge.
SUSPECT_CHECKS='
bugbot
(cursor|copilot|devin|korbit|codeant|codescene|gemini|claude|amazon q|graphite|diamond)[^a-z0-9]*(code[^a-z0-9]*)?review
code[^a-z0-9]*review
(ai|llm|automated|agent|bot)[^a-z0-9]*(code[^a-z0-9]*)?review
review[^a-z0-9]*(bot|agent)
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
REFUSALS_SENTINEL='
rate.limited by [a-z0-9._-]+
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

# --- table 3: positive evidence that an artifact IS a review ------------------
# A row here outranks table 2b — never table 2a. It exists because a reviewer's REVIEW
# comment routinely carries a notice about something it did NOT do, and table 2b reads
# the whole body:
#
#   > ## Review skipped
#   > Auto incremental reviews are disabled on this repository.
#
# sits at the top of the same comment that carries the walkthrough of a review that did
# happen — on this repository it is on 10 of 20 reviewed pull requests, because
# `.coderabbit.yaml` here sets `auto_incremental_review: false` on purpose. Reading that
# as "no review happened" mislabels the artifact, and the operator then reads a quoted
# refusal that is not why the PR is unmerged.
#
# WHAT THIS IS NOT. It is not a way to clear. An artifact that survives table 2 still has
# to name the CURRENT head to reach exit 0, so the worst case of a wrong row here is exit
# 4 (stale) rather than exit 1 (refused) — a different refusal, never a pass. The one
# shape that could turn into a pass is a rate-limit notice that also carried review
# evidence, since that notice quotes the head; that is what table 2a is for, and
# `tests/review-clearance.test.sh` asserts the recorded refusal carries no row from here.
REVIEWED='
# the reviewer emits its walkthrough marker only when it produced a walkthrough
walkthrough_start
# the two shapes of "I looked, and here is the count"
(no )?actionable comments (posted|were generated)
'

# --- table 4: an artifact that declares itself a review, structurally ---------
# The `okf-verdict` trailer (`SCHEMA.md` → "A verdict is a structured claim, not prose")
# is the fallback reviewer's own machine-readable output, and it outranks EVERY refusal
# row — including the sentinel.
#
# WHY, and it is not a convenience: a `qa-reviewer` verdict on a rate-limited PR has to
# SAY that the hosted reviewer refused, quoting the words and the sentinel, which
# classifies the verdict itself as a refusal. That happened to the verdict on the PR that
# introduced this script. Fencing the quote works only while the fences stay balanced,
# so the durable answer is the structured trailer the verdict already carries.
#
# This reads attacker-writable text, and that is bounded: only artifacts from the
# reviewer this run is asking about are classified at all, so the trailer can only be
# written by that reviewer. A hosted reviewer never emits one. And the trailer says only
# "a review happened" — SCHEMA.md's nine-clause predicate still adjudicates what it said.
VERDICTS='
<!--[[:space:]]*okf-verdict v[0-9]+
'

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  echo "                       [--reviewer <login>] [--for-check <check-name>]" >&2
  echo "       $(basename "$0") --match-check <check-name>   (0 reviewer's, 1 CI, 3 unknown)" >&2
  echo "       $(basename "$0") --self-test                  (prove this script RUNS)" >&2
  exit 2
}

# --- table lookups (no network, no PR) ---------------------------------------
# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

fold() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# The col-1 login patterns of every REVIEWERS row whose col-2 check pattern matches
# <check-name>. Empty when no row owns that check. Substring match, case-folded.
owners_of_check() {
  local needle; needle="$(fold "$1")"
  local row login check
  while IFS= read -r row; do
    # Fields via awk, never `set -- $row`: the rows are EREs and several end in `*`, so
    # word-splitting them would also pathname-expand them against the caller's cwd.
    login="$(printf '%s' "$row" | awk '{print $1}')"
    check="$(printf '%s' "$row" | awk '{print $2}')"
    [ -n "$login" ] && [ -n "$check" ] || continue
    printf '%s' "$needle" | grep -Eq "$check" 2>/dev/null && printf '%s\n' "$login"
  done <<EOF
$(rows "$REVIEWERS")
EOF
}

# Does <check-name> merely LOOK like a reviewer's, with no row owning it?
suspect_check() {
  local needle; needle="$(fold "$1")"
  local row
  while IFS= read -r row; do
    printf '%s' "$needle" | grep -Eq "$row" 2>/dev/null && return 0
  done <<EOF
$(rows "$SUSPECT_CHECKS")
EOF
  return 1
}

# Is <check-name> a reviewer's own status check?
#   0  yes, a table-1 row owns it       1  no, and it does not look like one either
#   3  it looks like a reviewer's and NO row owns it — unknown, so the caller refuses
match_check() {
  [ -n "$(owners_of_check "$1")" ] && return 0
  suspect_check "$1" && return 3
  return 1
}

# Does <login> match any of <newline-separated login patterns>? Whole-string,
# case-folded, "[bot]" stripped — the form every login test here takes.
match_patterns() {
  local login; login="$(fold "${1%\[bot\]}")"
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
# carry the executable bit, and a caller that reads their non-zero exit as "not a
# reviewer's check" clears an unreviewed PR. So `required-checks.sh` runs this first and
# refuses unless it exits 0 AND prints SELFTEST_OK verbatim — that string is the contract
# between the two files, and it is duplicated there on purpose (a shared constant would
# have to be sourced, and sourcing a broken file is the failure being tested for).
#
# THE TWO CONTROLS ARE THE POINT. Printing a banner would pass for any stub that prints a
# banner. This drives the table lookup the caller actually depends on, in both directions
# — a name that MUST classify as a reviewer's and one that MUST NOT — so a truncated copy
# whose tables are half-read fails here rather than answering "CI" to everything.
SELFTEST_OK="review-clearance: self-test ok"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  match_check "CodeRabbit" || {
    echo "self-test: the reviewer table no longer matches its own canary" >&2; exit 2; }
  if match_check "Build, Lint & Format"; then
    echo "self-test: the reviewer table matches a plain CI job" >&2; exit 2
  fi
  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

pr=""; repo=""; want_head=""; want_reviewer=""; for_check=""
if [ "${1:-}" = "--match-check" ]; then
  [ -n "${2:-}" ] && [ "$#" -eq 2 ] || usage
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

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found — cannot read reviewer state, so this refuses" >&2
    exit 2
  }
done

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- one fetch: the PR and every artifact on it -------------------------------
# ONE `gh` call, because the alternative — a call per artifact — is a network round trip
# per comment on every tick. `reviews` and `comments` are BOTH needed: a hosted reviewer
# may publish its verdict as a review object or, as the reviewer this was written against
# does, as a plain issue comment. Reading only `reviews` reports "no review" for a PR that
# was in fact reviewed, and reading only `comments` misses a human approval.
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,headRefOid,author,reviews,comments 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — refusing (fail closed)" >&2
  exit 2
}

meta="$(printf '%s' "$raw" | jq -r '[.url, .headRefOid, (.author.login // "")] | @tsv' 2>/dev/null)" || meta=""
url="$(printf '%s' "$meta" | cut -f1)"
head_sha="$(printf '%s' "$meta" | cut -f2)"
pr_author="$(printf '%s' "$meta" | cut -f3)"
[ -n "$url" ] && [ -n "$head_sha" ] || {
  echo "error: could not resolve the head SHA of PR $pr — refusing (fail closed)" >&2
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
if [ -n "$want_reviewer" ] && [ "$(fold "$want_reviewer")" = "$(fold "$pr_author")" ]; then
  echo "error: --reviewer $want_reviewer is the author of PR $pr — an author cannot be" >&2
  echo "       its own independent reviewer. Refusing." >&2
  exit 2
fi

# --- split the artifacts into files ------------------------------------------
# Bodies are multi-line markdown, so they cannot travel as TSV fields. jq emits a header
# line then the raw body; awk cuts on the header.
#
# THE SEPARATOR IS RANDOM PER RUN, and that is a security property rather than a style.
# Artifact bodies are attacker-writable text — anyone who can comment on a PR can write
# anything into one. A fixed sentinel could be typed into a comment to forge a record
# boundary and so fabricate an artifact with an author of the forger's choosing. Sixteen
# random bytes cannot be guessed in advance by the text being parsed.
SEP="okf-$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
[ "${#SEP}" -gt 16 ] || {
  echo "error: could not generate a record separator — refusing (fail closed)" >&2
  exit 2
}

printf '%s' "$raw" | jq -r --arg s "$SEP" '
    ( (.reviews[]?  | {kind:"review",  login:(.author.login // ""), state:(.state // ""), body:(.body // "")}),
      (.comments[]? | {kind:"comment", login:(.author.login // ""), state:"",             body:(.body // "")}) )
    | "\($s)\t\(.kind)\t\(.login)\t\(.state)", .body
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

# --- classification ----------------------------------------------------------
# Fenced code blocks are removed before the tables are applied, so a review that QUOTES
# refusal language — a diff of this very table, say — is not read as a refusal itself.
# Leading blockquote markers are stripped when testing for the fence, because reviewers
# wrap their notices in `>` quoting.
#
# UNBALANCED FENCES FAIL CLOSED, and that is not defensive dressing — a toggle with no
# END check is a one-character bypass. An artifact body is attacker-writable, so a single
# prepended ``` inverts the toggle: every subsequent line reads as "inside a fence", the
# stripped body comes back EMPTY, no table matches anything, and the recorded rate-limit
# refusal clears. So an odd count means "this body cannot be read as fenced markdown",
# and the whole raw body is handed back instead — refusal language then counts wherever
# it sits, which costs a human glance and cannot cost a merge.
#
# The opening marker's TYPE is carried too: ``` inside a ~~~ block is content, not a
# close, so a body that nests them stays balanced instead of drifting odd.
strip_fences() {
  awk '
    { raw[NR] = $0
      probe = $0; sub(/^[[:space:]]*((> ?)+)?[[:space:]]*/, "", probe)
      if (probe ~ /^```/)      marker = "```"
      else if (probe ~ /^~~~/) marker = "~~~"
      else                     marker = ""
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

# Every prefix of the head from 7 chars up, so an artifact may name the commit in full or
# abbreviated. Compared against the hex tokens in the body, never against a range syntax:
# the range is exactly what the refusal also carries.
: > "$TMPD/prefixes"
i=7
while [ "$i" -le "${#head_sha}" ]; do
  printf '%s\n' "$(printf '%s' "$head_sha" | cut -c1-"$i")" >> "$TMPD/prefixes"
  i=$((i + 1))
done

names_head() { # <stripped-body-file> — does this artifact name the current head at all?
  # Via a file rather than a pipe into `grep -q`: -q exits at the first match, and under
  # `pipefail` the SIGPIPE it raises upstream would surface as a failed pipeline.
  # Reads the SAME stripped text the tables do: two tests over two different renderings
  # of one body is the shape of the fence bug above, whichever way round they run.
  grep -Eo '[0-9a-fA-F]{7,40}' "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' > "$TMPD/toks"
  grep -qxF -f "$TMPD/prefixes" "$TMPD/toks"
}

hits() { # <table> <stripped-body-file> — the matching lines, or nothing
  rows "$1" > "$TMPD/pat"
  grep -Ei -f "$TMPD/pat" "$2" 2>/dev/null | head -3
}

refusal_hits() { # <stripped-body-file> — the refusal lines, from either tier
  { hits "$REFUSALS_SENTINEL" "$1"; hits "$REFUSALS" "$1"; } | head -3
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

n=0; considered=0; refusal_body=""; refusal_from=""; stale_from=""
while IFS=$'\t' read -r kind login state; do
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
    [ "$(fold "$login")" = "$(fold "$want_reviewer")" ] || continue
  else
    match_reviewer "$login" || continue
  fi
  # An author's own artifact is never independent, whichever table matched.
  [ "$(fold "$login")" = "$(fold "$pr_author")" ] && continue

  # A dismissed review has been withdrawn and a pending one was never submitted; neither
  # is evidence that anybody looked at this head.
  case "$state" in DISMISSED|PENDING) continue ;; esac

  considered=$((considered + 1))
  strip_fences "$body" > "$TMPD/stripped"

  # TEST 1 — did this artifact review anything? FIRST, always, because the refusal names
  # the head too, and a detector that pins first reads a refusal as a review. Three tiers,
  # highest first (see the tables): a structured verdict is a review whatever it quotes; a
  # machine sentinel is a refusal whatever else it carries; refusal PROSE is a refusal
  # only when nothing in the body evidences a review that did happen.
  if [ -z "$(hits "$VERDICTS" "$TMPD/stripped")" ]; then
    refusal=""
    if [ -n "$(hits "$REFUSALS_SENTINEL" "$TMPD/stripped")" ]; then
      refusal=yes
    elif [ -n "$(hits "$REFUSALS" "$TMPD/stripped")" ] \
      && [ -z "$(hits "$REVIEWED" "$TMPD/stripped")" ]; then
      refusal=yes
    fi
    if [ -n "$refusal" ]; then
      [ -n "$refusal_body" ] || { refusal_body="$TMPD/refusal"; refusal_from="$login"
                                  cp "$TMPD/stripped" "$TMPD/refusal"; }
      continue
    fi
  fi

  # TEST 2 — and only now, is this artifact about the commit we are clearing?
  if names_head "$TMPD/stripped"; then
    echo "ok: review artifact from $login ($kind) names head $head_sha on PR $pr"
    exit 0
  fi
  [ -n "$stale_from" ] || stale_from="$login ($kind)"
done < "$TMPD/index"

# --- nothing cleared: say precisely which shape this PR is -------------------
if [ -n "$refusal_body" ]; then
  echo "refuse: $refusal_from DECLINED to review PR $pr — this is not clearance, however" >&2
  echo "        green its status check is. It said:" >&2
  refusal_hits "$refusal_body" | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' \
                                     -e 's/^[*#[:space:]]*//' -e 's/[*[:space:]]*$//' \
                                     -e 's/^/          | /' >&2
  when="$(reopen_line "$refusal_body")"
  if [ -n "$when" ]; then
    echo "        Reopens: $when" >&2
  else
    echo "        No reopen time published — re-request a review once the quota resets." >&2
  fi
  echo "        A skipped PR is NOT re-reviewed automatically: nothing re-runs until a" >&2
  echo "        new commit lands or someone asks for a first review." >&2
  exit 1
fi

if [ -n "$stale_from" ]; then
  echo "refuse: the only artifact on PR $pr is from $stale_from and does not name head" >&2
  echo "        $head_sha — it reviewed an earlier commit, or names no commit at all." >&2
  echo "        A verdict for a commit that is no longer the head is stale. This is the" >&2
  echo "        ORDINARY outcome where the reviewer does not re-review on every push" >&2
  echo "        (CodeRabbit's \`auto_incremental_review: false\`): the review is real and" >&2
  echo "        it is not of this commit. Ask for a review at this head, or look." >&2
  exit 4
fi

echo "no-review: nothing on PR $pr from a known reviewer${want_reviewer:+ ($want_reviewer)}${for_check:+ (owner of '$for_check')}." >&2
echo "        $n artifact(s) on the PR, $considered from a reviewer. An absent review is" >&2
echo "        NOT a pass — surface the PR for a human, or dispatch the fallback reviewer." >&2
[ -n "$want_reviewer" ] || echo "        Pass --reviewer <login> if this repo uses a reviewer with no table row." >&2
exit 3
