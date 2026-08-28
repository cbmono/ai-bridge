#!/usr/bin/env bash
#
# check-dispatch.test.sh — exercises symlink/scripts/check-dispatch.sh, the two-second
# question a dispatch report cannot be trusted to answer about itself: **did the PR the
# agent said it would open actually get opened?**
#
# THE THREE SHAPES, and only one of them clears — each pinned against a tracked fixture
# under tests/fixtures/dispatch/:
#
#   1. success.task.md   status advanced, `pr:` names a PR the host resolves  → exit 0
#   2. parked.task.md    status unmoved, `pr:` empty (the incident)           → exit 1
#   3. ghost-pr.task.md  status advanced, `pr:` names a PR that is not there  → exit 3
#
# SHAPE 2 IS THE ONLY ONE THAT MATTERS, AND IT IS WHY THIS FILE IS SHAPED THE WAY IT IS.
# On 2026-08-28 two `software-engineer` agents finished their work, committed it (one had
# already pushed), then ended their turns waiting on a background job that nothing was left
# running to notify — and **reported as completed**. Every guard in the bundle passed them:
# the 30-40 minute wall-clock rule (one parked at 16 minutes), the two-round review cap
# (neither reached review), and the completion notification itself (that is what they
# sent). Only "does the PR exist?" would have caught it.
#
# So a suite that exercises only the success path proves nothing here — it is satisfied by
# a checker that believes every report. That is not a rhetorical worry: the CREDULOUS
# BASELINE section below builds exactly such a checker (`exit 0`, unconditionally), runs it
# against all three fixtures, and asserts it clears every one of them. Those assertions are
# the measuring stick for the real script's, immediately after: the difference between the
# two IS the value of this change, and if the parked assertion ever stops discriminating,
# the baseline block goes red first.
#
# REPORT-ONLY IS ASSERTED THREE WAYS, not described once. `/pm-loop` step 2 calls
# re-dispatching an already-finished task sequence "the most expensive failure" this loop
# has, so a checker that acted on its own reading would reintroduce it. Pinned by: a
# fingerprint of the whole fixture directory (contents AND modes) across every invocation;
# a log inside the `gh` stub, so every host call the script actually made is inspected and
# must be a read; and a static scan of the script's non-comment lines for mutating verbs.
#
# THE PARKED CATCH MUST SURVIVE WITHOUT A NETWORK. `status:` unmoved plus an empty `pr:` is
# decidable from the document alone, so it is asserted with `gh` removed from PATH entirely
# — while the success fixture, whose verdict genuinely needs the host, must then refuse
# (exit 2, cannot answer) rather than clear. A checker that goes quiet when the network does
# is the same failure wearing a different hat.
#
# `gh` is replaced by a stub on PATH, so the whole matrix runs offline.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "check-dispatch.test: cannot locate self" >&2; exit 2; }
REPO="$(cd "$HERE/.." && pwd)" || { echo "check-dispatch.test: cannot locate repo root" >&2; exit 2; }
SCRIPT="$REPO/symlink/scripts/check-dispatch.sh"
CONVENTIONS="$REPO/symlink/CONVENTIONS.md"
PM="$REPO/symlink/.claude/agents/project-manager.md"

FIXDIR="$HERE/fixtures/dispatch"
SUCCESS="$FIXDIR/success.task.md"
PARKED="$FIXDIR/parked.task.md"
GHOST="$FIXDIR/ghost-pr.task.md"

SUCCESS_PR="https://github.com/acme/widgets/pull/42"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-dispatch.XXXXXX")" || {
  echo "check-dispatch.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || {
  echo "check-dispatch.test: mktemp -d returned no usable directory — refusing to run." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- the gh stub ---------------------------------------------------------------------
# Two verbs, because the script reads two things and writes nothing: `pr view` resolves a
# URL, and `auth status` is what tells "this PR is not there" apart from "this machine
# cannot ask" — a distinction that decides between exit 3 and exit 2, i.e. between a real
# finding and a refusal. EVERY invocation is appended to $GHFIX/calls, whatever it is, so
# the report-only assertions below inspect what the script actually did rather than what
# its comments say it does. An unhandled verb exits 99 and is loud.
export GHFIX="$TMP/ghfix"
mkdir -p "$GHFIX" "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GHFIX/calls"
case "${1:-} ${2:-}" in
  "auth status")
    [ -f "$GHFIX/unauth" ] && { echo "gh: You are not logged into any GitHub hosts." >&2; exit 1; }
    echo "github.com: logged in"; exit 0 ;;
  "pr view")
    url="${3:-}"
    if grep -qxF "$url" "$GHFIX/existing" 2>/dev/null; then
      printf '{"url":"%s"}\n' "$url"; exit 0
    fi
    # Real `gh` reports an unresolvable PR on stderr and exits 1.
    echo "could not resolve to a PullRequest with the URL \"$url\"" >&2; exit 1 ;;
esac
echo "check-dispatch.test stub: unhandled gh $*" >&2; exit 99
STUB
chmod +x "$TMP/bin/gh"
printf '%s\n' "$SUCCESS_PR" > "$GHFIX/existing"
export PATH="$TMP/bin:$PATH"

rc_of() { # <task-doc> [extra args…] -> the script's exit code, output discarded
  bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?
}
out_of() { # <task-doc> -> stdout+stderr, for the one place the wording is the product
  bash "$SCRIPT" "$@" 2>&1
}

# fingerprint(): contents AND mode of every tracked fixture, so a script that rewrote a
# task document — the re-dispatch's quieter cousin — cannot pass this file.
fingerprint() {
  find "$FIXDIR" -type f -print0 2>/dev/null | LC_ALL=C sort -z | while IFS= read -r -d '' f; do
    printf '%s ' "$f"
    ls -l "$f" | awk '{print $1}'
    shasum "$f" 2>/dev/null | awk '{print $1}'
  done
}

echo "== the fixtures this whole file rests on actually exist =="
ok "the script under test exists"      "$([ -f "$SCRIPT" ] && echo yes || echo no)" yes
ok "success fixture exists"            "$([ -f "$SUCCESS" ] && echo yes || echo no)" yes
ok "parked fixture exists"             "$([ -f "$PARKED" ] && echo yes || echo no)" yes
ok "ghost-PR fixture exists"           "$([ -f "$GHOST" ] && echo yes || echo no)" yes
ok "the stub resolves the success PR"  "$(gh pr view "$SUCCESS_PR" --json url >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…and does not resolve the ghost"   "$(gh pr view "https://github.com/acme/widgets/pull/9999" --json url >/dev/null 2>&1 && echo yes || echo no)" no

FP_BEFORE="$(fingerprint)"
ok "the fixture fingerprint is non-empty (or the report-only check compares two blanks)" \
   "$([ -n "$FP_BEFORE" ] && echo yes || echo no)" yes

echo
echo "== the credulous baseline: what 'believing the report' scores on these same fixtures =="
# A checker that trusts the completion notice. This is not a straw man — it is precisely
# what the loop did on 2026-08-28, and a suite that only exercises the success path cannot
# tell it apart from the real script.
CREDULOUS="$TMP/credulous.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CREDULOUS"
chmod +x "$CREDULOUS"
ok "credulous checker clears the SUCCESS fixture"  "$(bash "$CREDULOUS" "$SUCCESS" >/dev/null 2>&1; echo $?)" 0
ok "credulous checker clears the PARKED fixture"   "$(bash "$CREDULOUS" "$PARKED"  >/dev/null 2>&1; echo $?)" 0
ok "credulous checker clears the GHOST fixture"    "$(bash "$CREDULOUS" "$GHOST"   >/dev/null 2>&1; echo $?)" 0

echo
echo "== the three shapes, against the real script =="
ok "success: status advanced + PR resolves     -> exit 0" "$(rc_of "$SUCCESS")" 0
ok "PARKED: status unmoved + no PR             -> exit 1" "$(rc_of "$PARKED")"  1
ok "ghost:  pr: names a PR that is not there   -> exit 3" "$(rc_of "$GHOST")"   3

echo
echo "== the parked verdict has to be readable, or the human ignores it =="
PARKED_OUT="$(out_of "$PARKED")"
ok "the parked verdict names the document"   "$(grep -qF "parked.task.md" <<<"$PARKED_OUT" && echo yes || echo no)" yes
ok "…says no PR was opened"                  "$(grep -qiE 'no (pull request|PR)' <<<"$PARKED_OUT" && echo yes || echo no)" yes
ok "…and quotes the status it is still at"   "$(grep -qF "in-progress" <<<"$PARKED_OUT" && echo yes || echo no)" yes

echo
echo "== the two halves disagreeing is its own answer (exit 4), not a pass and not the parked shape =="
# Built in TMP rather than tracked: these are consistency defects in the RECORD, a
# different class from the three shapes above, and each is one field away from a fixture.
mk_task() { # <file> <status> <pr-value> [kind]
  local f="$1" st="$2" pr="$3" kind="${4:-build}"
  cat > "$f" <<EOF
---
type: Task
title: synthetic
kind: $kind
status: $st
target_repo: acme/widgets
open_questions: []
pr: $pr
timestamp: 2026-08-28T00:00:00Z
---

# Context
EOF
}
mk_task "$TMP/claims-review.md" in-review "[ ]"
mk_task "$TMP/pr-but-unmoved.md" in-progress "[\"$SUCCESS_PR\"]"
mk_task "$TMP/done-no-pr.md" done "[ ]"
ok "in-review with an empty pr:            -> exit 4" "$(rc_of "$TMP/claims-review.md")"   4
ok "done with an empty pr:                 -> exit 4" "$(rc_of "$TMP/done-no-pr.md")"      4
ok "a resolvable PR but status never moved -> exit 4" "$(rc_of "$TMP/pr-but-unmoved.md")"  4

echo
echo "== an honest stop is not a failure, and a research task is not a question this can answer =="
mk_task "$TMP/blocked.md" blocked "[ ]"
mk_task "$TMP/research.md" in-progress "[ ]" research
mk_task "$TMP/ready-clean.md" ready "[ ]"
ok "blocked with no PR: an honest stop     -> exit 0" "$(rc_of "$TMP/blocked.md")"  0
ok "kind: research has no PR to look for   -> exit 2" "$(rc_of "$TMP/research.md")" 2
ok "a task still at ready with no PR reads as parked too -> exit 1" "$(rc_of "$TMP/ready-clean.md")" 1

echo
echo "== the pr: field is read in every spelling task documents actually use =="
# Recorded from real task documents: quoted, bare, space-padded, and the block sequence.
mk_task "$TMP/pr-bare.md"   in-review "[ $SUCCESS_PR ]"
mk_task "$TMP/pr-padded.md" in-review "[ \"$SUCCESS_PR\" ]"
cat > "$TMP/pr-block.md" <<EOF
---
type: Task
title: synthetic
kind: build
status: in-review
pr:
  - $SUCCESS_PR
timestamp: 2026-08-28T00:00:00Z
---

# Context
EOF
ok "pr: [ url ]        (unquoted)   -> exit 0" "$(rc_of "$TMP/pr-bare.md")"   0
ok "pr: [ \"url\" ]      (padded)     -> exit 0" "$(rc_of "$TMP/pr-padded.md")" 0
ok "pr: as a block sequence          -> exit 0" "$(rc_of "$TMP/pr-block.md")"  0

# A `pr:` carrying something that is not a URL is a claim with nothing behind it, which is
# the ghost shape, not the parked one — the report DID say it produced something.
mk_task "$TMP/pr-prose.md" in-review "[ pending ]"
ok "pr: naming something that is not a URL -> exit 3" "$(rc_of "$TMP/pr-prose.md")" 3

# A second PR that does not resolve must not be masked by a first one that does — a task
# may fan out to several PRs (SCHEMA.md), and only checking `pr[0]` would clear it.
mk_task "$TMP/pr-two.md" in-review "[ $SUCCESS_PR, https://github.com/acme/widgets/pull/9999 ]"
ok "one PR resolves, the second does not   -> exit 3" "$(rc_of "$TMP/pr-two.md")" 3

echo
echo "== it refuses rather than guesses: usage, missing file, unreadable frontmatter =="
mk_task "$TMP/no-status.md" "" "[ ]"
printf 'no frontmatter here at all\n' > "$TMP/bodyonly.md"
printf -- '---\ntype: Task\nstatus: in-progress\n' > "$TMP/unterminated.md"
ok "no argument                     -> exit 2" "$(bash "$SCRIPT" >/dev/null 2>&1; echo $?)" 2
ok "two arguments                   -> exit 2" "$(rc_of "$PARKED" "$SUCCESS")" 2
ok "a file that is not there        -> exit 2" "$(rc_of "$TMP/nope.md")" 2
ok "a document with no frontmatter  -> exit 2" "$(rc_of "$TMP/bodyonly.md")" 2
ok "frontmatter that never closes   -> exit 2" "$(rc_of "$TMP/unterminated.md")" 2
ok "an empty status:                -> exit 2" "$(rc_of "$TMP/no-status.md")" 2

echo
echo "== the parked catch must not depend on the network; a needed-but-unavailable host must refuse =="
# `status:` unmoved and `pr:` empty is decidable from the document alone. Removing `gh`
# from PATH entirely proves the catch survives an offline machine, a missing CLI and a
# rate limit — and, in the same breath, that the success verdict does NOT quietly clear
# when the one thing that could contradict it cannot be asked.
BARE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
GH_IN_BARE="$(PATH="$BARE_PATH" command -v gh 2>/dev/null || true)"
ok "precondition: no gh on the bare PATH (else the next two prove nothing)" \
   "$([ -z "$GH_IN_BARE" ] && echo yes || echo no)" yes
ok "no gh at all, parked fixture    -> still exit 1" \
   "$(PATH="$BARE_PATH" bash "$SCRIPT" "$PARKED" >/dev/null 2>&1; echo $?)" 1
ok "no gh at all, success fixture   -> exit 2, never 0" \
   "$(PATH="$BARE_PATH" bash "$SCRIPT" "$SUCCESS" >/dev/null 2>&1; echo $?)" 2
# gh present but unauthenticated: "cannot ask" must never be reported as "not there".
: > "$GHFIX/unauth"
ok "gh present but unauthenticated  -> exit 2, not 3" "$(rc_of "$GHOST")" 2
rm -f "$GHFIX/unauth"
ok "…and with auth restored the ghost is a finding again -> exit 3" "$(rc_of "$GHOST")" 3

echo
echo "== REPORT-ONLY: it never re-dispatches, never writes, and only ever asks =="
# 1. Everything it did to the host, from the stub's own log.
CALLS="$(cat "$GHFIX/calls" 2>/dev/null)"
ok "the script actually called gh (or the next assertion is vacuous)" \
   "$([ -n "$CALLS" ] && echo yes || echo no)" yes
NON_READ="$(grep -vE '^(pr view |auth status)' <<<"$CALLS" | grep -v '^$' | wc -l | tr -d ' ')"
ok "every gh call it made was a read (pr view / auth status)" "$NON_READ" 0
ok "it never asked the host to create anything" \
   "$(grep -qE '(pr create|pr merge|pr edit|pr comment|pr close|pr ready|api .*-X)' <<<"$CALLS" && echo yes || echo no)" no

# 2. Nothing on disk moved, across every invocation above.
FP_AFTER="$(fingerprint)"
if [ "$FP_BEFORE" != "$FP_AFTER" ]; then
  echo "check-dispatch.test: the fixtures CHANGED while this harness ran:" >&2
  diff <(printf '%s\n' "$FP_BEFORE") <(printf '%s\n' "$FP_AFTER") >&2 || true
fi
ok "the fixture documents are byte-for-byte as they were found" \
   "$([ "$FP_BEFORE" = "$FP_AFTER" ] && echo yes || echo no)" yes

# 3. Static: no mutating verb in the script's executable text. Full-line comments are
# stripped first — this file's whole subject is verbs it must not use, and the script says
# so in prose. A trailing comment is NOT stripped (that needs a shell parser, not a sed),
# so any prose naming one of these verbs belongs on its own comment line. Stated as a
# limit rather than papered over.
CODE="$(grep -vE '^[[:space:]]*#' "$SCRIPT")"
ok "the code body is non-empty after stripping comments" \
   "$([ -n "$CODE" ] && echo yes || echo no)" yes
for verb in 'gh pr create' 'gh pr merge' 'gh pr edit' 'gh pr comment' 'git push' 'git commit' 'git add' 'sed -i' 'claude ' 'Agent tool' 'subagent_type'; do
  ok "no '$verb' in the script's executable text" \
     "$(grep -qF -- "$verb" <<<"$CODE" && echo yes || echo no)" no
done
# The task document is only ever opened for READING. Any redirection onto the argument is
# the write this whole check exists to forbid.
ok "the script never redirects onto its argument" \
   "$(grep -qE '>[[:space:]]*"?\$(TASK|task|1)' <<<"$CODE" && echo yes || echo no)" no

echo
echo "== wiring: the rule reaches the two places a dispatch is believed =="
# Criterion 3. The ad-hoc path — a main session dispatching an agent with no PM tick
# involved — is the one with no coverage today, so the CONVENTIONS bullet must say so in
# the same breath as it names the script, exactly as the resolve-model.sh rule does.
bullet_of() { # <file> <regex> — the whole `- ` bullet containing <regex>
  awk -v n="$2" 'BEGIN{buf=""}
    /^- / { if (buf ~ n) { print buf; exit } ; buf=$0; next }
    { buf = buf "\n" $0 }
    END { if (buf ~ n) print buf }' "$1"
}
CONV_BULLET="$(bullet_of "$CONVENTIONS" "check-dispatch")"
ok "CONVENTIONS.md names scripts/check-dispatch.sh in a bullet of its own" \
   "$([ -n "$CONV_BULLET" ] && echo yes || echo no)" yes
ok "…giving the exact path to run"  "$(grep -qF 'scripts/check-dispatch.sh' <<<"$CONV_BULLET" && echo yes || echo no)" yes
ok "…covering the ad-hoc dispatch path explicitly" \
   "$(grep -qF 'ad-hoc' <<<"$CONV_BULLET" && echo yes || echo no)" yes
ok "…and saying the check never re-dispatches" \
   "$(grep -qiE 'report-only|never (re-)?dispatch' <<<"$CONV_BULLET" && echo yes || echo no)" yes

# Literal prefixes, matched with index() rather than a regex: `-v` strings are escape-
# processed before awk ever sees them, so a pattern like '^4\. \*\*' arrives as `^4. **`
# — a `*` with nothing to repeat — and silently matches nothing. Both section extractions
# are asserted non-empty below for exactly that reason.
section_of() { # <file> <start-literal-prefix> <end-literal-prefix>
  awk -v s="$2" -v e="$3" '
    index($0, s) == 1 { on = 1 }
    on { print }
    on && index($0, e) == 1 && index($0, s) != 1 { exit }' "$1"
}
PM_DISPATCH="$(section_of "$PM" '3. **Dispatch' '4. **')"
PM_ADVANCE="$(section_of "$PM" '4. **Advance' '5. **')"
ok "the PM dispatch step was extractable (or the next assertions are vacuous)" \
   "$([ -n "$PM_DISPATCH" ] && echo yes || echo no)" yes
ok "the PM advance step was extractable" \
   "$([ -n "$PM_ADVANCE" ] && echo yes || echo no)" yes
ok "step 3 (dispatch) names check-dispatch.sh" \
   "$(grep -qF 'scripts/check-dispatch.sh' <<<"$PM_DISPATCH" && echo yes || echo no)" yes
ok "step 4 (a role agent has reported) names check-dispatch.sh" \
   "$(grep -qF 'scripts/check-dispatch.sh' <<<"$PM_ADVANCE" && echo yes || echo no)" yes
ok "…and step 4 says a non-zero verdict is not a re-dispatch" \
   "$(grep -qiE 'never (a )?re-dispatch|do not re-dispatch|not a re-dispatch' <<<"$PM_ADVANCE" && echo yes || echo no)" yes

# --- the assertion total ---------------------------------------------------------------
# A block that is skipped rather than failed still turns this file red. Move this number
# in the same commit that adds or removes an assertion.
EXPECTED_ASSERTIONS=64
TOTAL=$((pass + fail))
ok "exactly $EXPECTED_ASSERTIONS assertions ran (a silently skipped block shows up here)" \
   "$TOTAL" "$EXPECTED_ASSERTIONS"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
