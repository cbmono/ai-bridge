#!/usr/bin/env bash
#
# check-dispatch.sh — did the dispatch produce the artifact it promised?
#
#   Usage: scripts/check-dispatch.sh <task-doc>
#
# Run it whenever a dispatched agent reports — from a `/pm-loop` tick or from an ad-hoc
# dispatch in a main session. It reads three things and judges nothing else:
#
#   1. did the task's `status:` advance off `ready`/`in-progress`;
#   2. does its `pr:` name a URL;
#   3. does that pull request actually exist, per the host.
#
# WHY IT EXISTS. On 2026-08-28 two role agents finished their work, committed it — one had
# already pushed — then ended their turns waiting on a background job that nothing was left
# running to notify, and **reported as completed**. No PR was ever opened. Every guard in
# the bundle passed them: the 30-40 minute wall-clock rule (one parked at 16 minutes), the
# two-round review cap (neither reached review), and the completion notification itself,
# which is what they sent. The only thing that would have caught it is the question above,
# and nothing was asking it.
#
# IT IS REPORT-ONLY, AND THAT IS THE LOAD-BEARING PROPERTY. It never re-dispatches, never
# writes to the task document, never touches a branch, and asks the host only to READ.
# `/pm-loop` step 2 calls re-dispatching an already-finished task sequence the most
# expensive failure a loop of this shape has — a checker that acted on its own reading
# would reintroduce exactly that, and would do it automatically. The verdict goes to a
# human or to the loop's own reasoning; the recovery is usually one message to the parked
# agent ("open the PR on what you already have"), which is cheap, and anything more is a
# decision somebody makes with the whole picture. Not this script's call.
#
# IT IS ALSO DELIBERATELY DUMBER THAN THE DIAGNOSIS. It does not read the diff, judge the
# work, or decide whether the PR is any good — that is the independent reviewer's job
# (SCHEMA.md → "Independent verification gate"). It answers one question a report cannot be
# trusted to answer about itself.
#
# Exit codes — 0 is the only clearance; every other code wants a human's eyes:
#
#   0  the dispatch produced what it promised (or stopped honestly: `blocked`/`cancelled`)
#   1  PARKED — status still `draft`/`ready`/`in-progress` and no PR. THE signature.
#   2  cannot answer: usage, no such file, unreadable frontmatter, a research task (it has
#      no PR by design — read its `artifacts:`), or `gh` missing/unauthenticated when a
#      recorded URL still had to be resolved. Unknown is never reported as fine.
#   3  the claim is not backed: `pr:` names a pull request the host does not resolve, or
#      names something that is not a URL at all.
#   4  the record contradicts itself: `in-review`/`done` with an empty `pr:`, or a PR that
#      resolves while `status:` never moved. Usually one edit away from correct.
#
# THE PARKED CATCH NEEDS NO NETWORK, on purpose: an unmoved status with an empty `pr:` is
# decided from the document alone, before the host is consulted at all, so an offline
# machine, a missing CLI or a rate limit cannot silence the one verdict this exists for.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/check-dispatch.test.sh.
set -uo pipefail

usage() {
  echo "Usage: $(basename "$0") <task-doc>" >&2
  exit 2
}

case "${1:-}" in -h|--help) usage ;; -*) echo "error: unknown option '$1'" >&2; usage ;; esac
[ "$#" -eq 1 ] || usage
TASK="$1"
[ -f "$TASK" ] || { echo "error: no such task document: $TASK" >&2; exit 2; }

# Print the frontmatter block. Exit 3 when the file does not open with `---`, exit 4 when
# it opens but never closes — the same reader validate-bundle.sh and task-owner.sh use, for
# the same reason: an unterminated block would return the whole file, and a `pr:` line in
# the BODY (prose, a note, a quoted example) would be read as the record.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

fm=""; fm_rc=0
fm="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "error: $TASK has no readable YAML frontmatter, so what the dispatch was" >&2
  echo "       supposed to produce cannot be read. Refusing rather than guessing." >&2
  exit 2
}

# Only the FIRST occurrence of a key counts. A document with the key repeated would
# otherwise be judged from the LATER value — the bug push-state.sh had with `status:`.
field() { # <key>
  printf '%s\n' "$fm" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*$/, "", v)
      sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# The `pr:` VALUE, which in real task documents is a flow list (`["url"]`, `[ url ]`,
# `[ "url" ]`, two entries comma-separated) or a block sequence on the following lines.
# Everything from the key up to the next column-0 key is the value, per YAML — so this
# reads all of them without caring which spelling was used.
pr_region() {
  printf '%s\n' "$fm" | awk '
    !seen && index($0, "pr:") == 1 { seen = 1; blk = 1; v = $0; sub(/^pr:[[:space:]]*/, "", v); print v; next }
    blk && /^[[:space:]]/ { print; next }
    blk { blk = 0 }'
}

status="$(field status)"
kind="$(field kind)"
region="$(pr_region)"

# What the field CLAIMS, with the list syntax stripped: empty means the agent recorded no
# artifact at all, which is a different finding from recording an unusable one.
claim="$(printf '%s' "$region" | tr -d '[]",'"'" | tr -d '[:space:]')"
# ...and the URLs inside it. A pull-request URL is the only thing here that can be resolved.
urls="$(printf '%s\n' "$region" | grep -oE 'https?://[^]"'"'"' ,]+/pull/[0-9]+')"

[ -n "$status" ] || {
  echo "error: $TASK records no status:, so whether the dispatch advanced it is" >&2
  echo "       unknown — and unknown is not a pass. Refusing." >&2
  exit 2
}

# A research task produces a deliverable, never a PR (SCHEMA.md), so "is there a PR?" is
# not a question about it. Say so and refuse, rather than inventing a verdict out of an
# absence that is correct.
if [ "$kind" = "research" ]; then
  echo "cannot answer: $TASK is kind: research — it has no PR by design." >&2
  echo "               Check its artifacts: and the deliverable itself instead." >&2
  exit 2
fi

case "$status" in
  draft|ready|in-progress) advanced=no ;;
  blocked|cancelled)       advanced=stopped ;;
  *)                       advanced=yes ;;
esac

# --- the parked signature, decided from the document alone --------------------------
# Deliberately before the host is consulted: this verdict must survive an offline machine.
if [ "$advanced" = "no" ] && [ -z "$claim" ]; then
  echo "PARKED: $TASK is still at status: $status and names no pull request." >&2
  echo "        The agent reported, but nothing it promised is on the host. Read its" >&2
  echo "        final message: the work is often already committed, sometimes already" >&2
  echo "        pushed, and one message asking it to open the PR recovers it." >&2
  echo "        This is a report, not an instruction — deciding what to do with it," >&2
  echo "        including whether anything is dispatched, stays with the human." >&2
  exit 1
fi

# --- resolve every URL the record claims --------------------------------------------
# The host is only needed from here on. A missing or unauthenticated CLI means the claim
# cannot be checked, which is unknown state — never "the PR is not there" (exit 3), and
# never a pass.
missing=""
if [ -n "$urls" ]; then
  command -v gh >/dev/null 2>&1 || {
    echo "cannot answer: gh is not installed, so the pull request(s) $TASK claims" >&2
    echo "               cannot be resolved. Unknown is not a pass — refusing." >&2
    exit 2
  }
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if gh pr view "$u" --json url >/dev/null 2>&1; then
      echo "ok: $u exists"
    elif ! gh auth status >/dev/null 2>&1; then
      echo "cannot answer: gh cannot reach the host (not logged in), so whether" >&2
      echo "               $u exists is unknown. Refusing rather than reporting a" >&2
      echo "               missing PR that may be perfectly fine." >&2
      exit 2
    else
      missing="$missing $u"
    fi
  done <<EOF
$urls
EOF
fi

if [ -n "$missing" ]; then
  echo "NOT THERE: $TASK claims a pull request the host does not resolve:" >&2
  for u in $missing; do echo "           $u" >&2; done
  echo "           A deleted branch, a URL written from memory, or a PR opened" >&2
  echo "           against the wrong repository all land here." >&2
  exit 3
fi

# A `pr:` with content but no URL in it — `[ pending ]`, a branch name, a bare number — is
# a claim with nothing resolvable behind it. The report DID say it produced something, so
# this is the unbacked-claim shape, not the parked one.
if [ -n "$claim" ] && [ -z "$urls" ]; then
  echo "NOT A URL: $TASK has pr: $region" >&2
  echo "           which names no pull request URL, so nothing can be resolved." >&2
  exit 3
fi

if [ "$advanced" = "yes" ] && [ -z "$urls" ]; then
  echo "MISMATCH: $TASK reads status: $status but names no pull request." >&2
  echo "          One of the two is wrong: either the PR was never opened, or it was" >&2
  echo "          opened and never recorded. Read the agent's report before acting." >&2
  exit 4
fi

if [ "$advanced" = "no" ] && [ -n "$urls" ]; then
  echo "MISMATCH: $TASK names a pull request that exists, but status: is still" >&2
  echo "          $status. The work landed; the record did not move. That is a" >&2
  echo "          document edit, never a reason to dispatch the task again." >&2
  exit 4
fi

if [ "$advanced" = "stopped" ]; then
  echo "ok: $TASK reports status: $status — an honest stop, no PR expected."
  echo "    Read the stated reason; this check has nothing further to say about it."
  exit 0
fi

echo "ok: $TASK advanced to status: $status and every pull request it names exists."
exit 0
