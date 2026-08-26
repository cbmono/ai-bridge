#!/usr/bin/env bash
#
# review-clearance.sh — assert that an independent review ARTIFACT exists on a pull
# request, at its current head. This is precondition 2 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is precondition 1, and
# calls in here whenever one of the REQUIRED checks turns out to be a reviewer's own.
#
#   Usage: scripts/review-clearance.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#                                           [--reviewer <login>]
#          scripts/review-clearance.sh --match-check <check-name>
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
# PROVIDER-AGNOSTIC BY CONSTRUCTION. Every vendor-specific string lives in one of the two
# tables below and nowhere else in this file: REVIEWERS (who counts as a reviewer, and
# what its status check is called) and REFUSALS (the language of "I did not review").
# Adopting a different reviewer is a row, not a rewrite. An unrecognised reviewer is not
# a pass — it is exit 3, which refuses — so the failure mode of a stale table is a human
# looking, never a merge.
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
# pass. A review this script cannot see is a review that did not happen.
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

# --- table 2: the language of "I did not review" -----------------------------
# One POSIX ERE per line, matched case-insensitively against an artifact body whose
# fenced code blocks have been removed (see strip_fences). Blank lines and whole-line
# `#` comments are ignored; a pattern may not carry a trailing comment, because the
# whole line is the pattern.
#
# THE FIRST ROW IS THE ONE THAT MATTERS and it is not prose: hosted reviewers mark their
# own automated notices with an HTML sentinel, which is a machine-readable signal sitting
# in a comment body. The rows after it are the human-visible phrasings, kept generic
# enough to catch a reviewer that reworded — and deliberately over-broad, because a false
# refusal costs a human glance while a missed refusal costs an unreviewed merge.
REFUSALS='
# the HTML sentinel a reviewer stamps on its own rate-limit notice
rate.limited by [a-z0-9._-]+
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

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>] [--reviewer <login>]" >&2
  echo "       $(basename "$0") --match-check <check-name>" >&2
  exit 2
}

# --- table lookups (no network, no PR) ---------------------------------------
# `rows <table>` strips comments and blank lines; both tables are read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

fold() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Is <check-name> a reviewer's own status check? Substring match, case-folded.
match_check() {
  local needle; needle="$(fold "$1")"
  local row pat
  while IFS= read -r row; do
    pat="$(printf '%s' "$row" | awk '{print $2}')"
    [ -n "$pat" ] || continue
    printf '%s' "$needle" | grep -Eq "$pat" 2>/dev/null && return 0
  done <<EOF
$(rows "$REVIEWERS")
EOF
  return 1
}

# Is <login> a known reviewer account? Whole-string match, case-folded, "[bot]" stripped.
match_reviewer() {
  local login; login="$(fold "${1%\[bot\]}")"
  local row pat
  while IFS= read -r row; do
    pat="$(printf '%s' "$row" | awk '{print $1}')"
    [ -n "$pat" ] || continue
    printf '%s' "$login" | grep -Eqx "$pat" 2>/dev/null && return 0
  done <<EOF
$(rows "$REVIEWERS")
EOF
  return 1
}

# --- argument parsing --------------------------------------------------------
pr=""; repo=""; want_head=""; want_reviewer=""
if [ "${1:-}" = "--match-check" ]; then
  [ -n "${2:-}" ] && [ "$#" -eq 2 ] || usage
  match_check "$2" && exit 0
  exit 1
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)     repo="${2:-}";           [ -n "$repo" ] || usage; shift 2 ;;
    --head)     want_head="${2:-}";      [ -n "$want_head" ] || usage; shift 2 ;;
    --reviewer) want_reviewer="${2:-}";  [ -n "$want_reviewer" ] || usage; shift 2 ;;
    -h|--help)  usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

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
# Fenced code blocks are removed before the refusal table is applied, so a review that
# QUOTES refusal language — a diff of this very table, say — is not read as a refusal
# itself. Leading blockquote markers are stripped when testing for the fence, because
# reviewers wrap their notices in `>` quoting.
strip_fences() {
  awk '
    { probe = $0; sub(/^[[:space:]]*((> ?)+)?[[:space:]]*/, "", probe) }
    probe ~ /^(```|~~~)/ { infence = !infence; next }
    !infence { print }
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

names_head() { # <body-file> — does this artifact name the current head at all?
  # Via a file rather than a pipe into `grep -q`: -q exits at the first match, and under
  # `pipefail` the SIGPIPE it raises upstream would surface as a failed pipeline.
  grep -Eo '[0-9a-fA-F]{7,40}' "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' > "$TMPD/toks"
  grep -qxF -f "$TMPD/prefixes" "$TMPD/toks"
}

refusal_hits() { # <body-file> — the refusal lines, or nothing
  rows "$REFUSALS" > "$TMPD/refusals"
  strip_fences "$1" | grep -Ei -f "$TMPD/refusals" 2>/dev/null | head -3
}

reopen_line() { # <body-file> — when the reviewer published a reopen time, quote it
  strip_fences "$1" | grep -Ei \
    -e 'next .{0,20}(review|run).{0,20}(available|in) ' \
    -e '(limit|quota|it) (will )?(reset|resets|resetting)' \
    -e 'try again (in|at|after) ' \
    -e 'available (again )?(in|at) ' \
    | head -1 | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' -e 's/^[*#[:space:]]*//' \
                    -e 's/[*[:space:]]*$//'
}

n=0; considered=0; refusal_body=""; refusal_from=""; stale_from=""
while IFS=$'\t' read -r kind login state; do
  n=$((n + 1))
  body="$TMPD/body.$n"
  [ -f "$body" ] || : > "$body"
  [ -n "$login" ] || continue

  # Whose opinion counts. With --reviewer it is exactly that account; without it, the
  # REVIEWERS table decides — and an account in neither is ignored rather than trusted,
  # so a teammate's "lgtm" comment never stands in for the independent gate.
  if [ -n "$want_reviewer" ]; then
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

  # TEST 1 — refusal language. FIRST, always: the refusal names the head too.
  hits="$(refusal_hits "$body")"
  if [ -n "$hits" ]; then
    [ -n "$refusal_body" ] || { refusal_body="$body"; refusal_from="$login"; }
    continue
  fi

  # TEST 2 — and only now, is this artifact about the commit we are clearing?
  if names_head "$body"; then
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
  echo "        A verdict for a commit that is no longer the head is stale." >&2
  exit 4
fi

echo "no-review: nothing on PR $pr from a known reviewer${want_reviewer:+ ($want_reviewer)}." >&2
echo "        $n artifact(s) on the PR, $considered from a reviewer. An absent review is" >&2
echo "        NOT a pass — surface the PR for a human, or dispatch the fallback reviewer." >&2
[ -n "$want_reviewer" ] || echo "        Pass --reviewer <login> if this repo uses a reviewer with no table row." >&2
exit 3
