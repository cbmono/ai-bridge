#!/usr/bin/env bash
#
# review-clearance.test.sh — exercises precondition 2 of the delegated merge gate,
# symlink/scripts/review-clearance.sh.
#
# THE THREE SHAPES, and only one of them clears:
#
#   1. a real review        → exit 0    (tests/fixtures/reviewer/clean-review.pr29.md)
#   2. a REFUSAL behind a green check → exit 1
#                              (tests/fixtures/reviewer/rate-limit-refusal.pr30.md)
#   3. no reviewer signal at all      → exit 3
#
# Shapes 1 and 2 are RECORDED, verbatim, from the two pull requests where this went
# wrong: #29 was reviewed, #30 and #31 were refused behind an identically green check
# and merged unreviewed, one of them shipping a shell script at mode 100644. Handwritten
# samples would prove nothing here — the whole difficulty is that the two real bodies
# look alike, and only a real one can show how alike.
#
# THE FALSE POSITIVE THIS FILE EXISTS TO PIN. The refusal comment carries the same
# "between <base> and <head>" range a real review carries, and on #30 that head WAS the
# PR head. So the obvious detector — "does an artifact name the current head" — returns
# TRUE for the refusal. `the trap` section below asserts that property of the fixture
# first (so the test fails if the evidence ever changes) and then asserts the script
# refuses anyway. Get the order of the two classifications wrong and this file goes red.
#
# `gh` and `jq` are replaced by stubs on PATH, so the whole matrix runs offline; the jq
# stub delegates to the real one unless a fixture asks it to break.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/review-clearance.sh"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer"
CLEAN="$FIXTURES/clean-review.pr29.md"
REFUSAL="$FIXTURES/rate-limit-refusal.pr30.md"
CLEAN_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
REFUSAL_HEAD="88c106a8dd2b9ae14e001918022d4909e5357460"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-clearance.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- stubs -------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for review-clearance.sh: one shape of call, answered from $FIX/pr_json.
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/gh_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    [ -f "$FIX/pr_json" ] || { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json" ;;
  *) echo "stub: unhandled gh $*" >&2; exit 99 ;;
esac
STUB
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
# The real jq, unless a case asks for a reader that cannot answer.
[ -f "\$FIX/jq_broken" ] && { echo "jq: broken pipe of a parser" >&2; exit 5; }
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

# --- fixture builders ---------------------------------------------------------
HEAD=""; AUTHOR=""; REVIEWS=""; COMMENTS=""

setup() { # start from: a readable PR at <head>, authored by "dev", with no artifacts
  rm -rf "$FIX"; mkdir -p "$FIX"
  HEAD="${1:-$CLEAN_HEAD}"; AUTHOR="dev"; REVIEWS='[]'; COMMENTS='[]'
}

body_file() { # <text...> -> a file holding it, so every artifact arrives the same way
  local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

add_comment() { # <login> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --rawfile b "$2" \
              '. + [{author:{login:$l}, body:$b}]' <<<"$COMMENTS")"
}

add_review() { # <login> <state> <body-file>
  REVIEWS="$("$REAL_JQ" --arg l "$1" --arg s "$2" --rawfile b "$3" \
             '. + [{author:{login:$l}, state:$s, body:$b}]' <<<"$REVIEWS")"
}

write_pr() {
  "$REAL_JQ" -n --arg h "$HEAD" --arg a "$AUTHOR" \
    --argjson rv "$REVIEWS" --argjson cm "$COMMENTS" \
    '{url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
      author:{login:$a}, reviews:$rv, comments:$cm}' > "$FIX/pr_json"
}

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args to the script...]
  write_pr
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
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
    printf '  FAIL  %-58s missing %s in: %s\n' "$1" "$2" "$(printf '%s' "$LAST_OUT" | head -2 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

assert() { # <name> <rc-of-a-condition>
  if [ "$2" = 0 ]; then printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %-58s\n' "$1"; fail=$((fail+1)); fi
}
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

echo "== the fixtures are the real thing =="
assert "the recorded refusal exists"     "$(yes_if test -s "$REFUSAL")"
assert "the recorded clean review exists" "$(yes_if test -s "$CLEAN")"

echo
echo "== shape 1: a real review clears =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the recorded clean review -> clear" 0
says   "  ...naming the reviewer that produced the artifact" "coderabbitai"
says   "  ...and the head it is pinned to" "$CLEAN_HEAD"

# The reviewer publishes its verdict as a plain issue comment on this repo, but a review
# OBJECT is the other half of the contract and must clear the same way.
setup "$CLEAN_HEAD"; add_review coderabbitai COMMENTED "$CLEAN"
expect "the same body as a review object -> clear" 0

echo
echo "== shape 2: a refusal behind a green check is NOT clearance =="
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "the recorded rate-limit refusal -> refuse" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
says   "  ...and saying when the quota reopens" "44 minutes"
says   "  ...and saying plainly this is not clearance" "not clearance"
says   "  ...and that nothing re-reviews it automatically" "NOT re-reviewed automatically"

echo
echo "== the trap: the refusal CONTAINS the PR's head, and must still refuse =="
# Assert the property of the evidence first. If this ever stops holding, the test below
# is no longer testing anything and should fail loudly rather than pass vacuously.
assert "the refusal comment names the PR head verbatim" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$REFUSAL")"
assert "…and so does the clean review (same shape, same range line)" \
  "$(yes_if grep -Fq "$CLEAN_HEAD" "$CLEAN")"
assert "…so a head-range detector cannot tell them apart" \
  "$(yes_if bash -c 'grep -Fq "between" "$1" && grep -Fq "between" "$2"' _ "$REFUSAL" "$CLEAN")"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "…and the refusal at its own head still refuses" 1

# The other side of the same ordering: refusal LANGUAGE quoted inside a fenced code block
# is a review discussing a refusal, not a refusal. Without this, a review of this very
# script's pattern table would classify as the thing it describes.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed at $CLEAN_HEAD — one nit." \
  '```' \
  'review limit reached' \
  'rate limited by some-reviewer.example' \
  '```' \
  'Otherwise looks good.')"
expect "refusal language inside a code fence -> still a review" 0

echo
echo "== an UNBALANCED fence must fail closed, not blank the body =="
# The bypass this section pins: strip_fences used to toggle on every marker with no END
# check, so an ODD count left everything after the marker "inside a fence" and the
# stripped body came back empty — no refusal matched, and the raw text still named the
# head, so the recorded refusal CLEARED. One character, typed into a comment.
#
# The control is the assertion above this line: with BALANCED fences the strip still
# happens, so these cases fail for the unbalance and not because fencing stopped working.
fenced_refusal="$TMP/refusal-one-fence.md"
{ printf '```\n'; cat "$REFUSAL"; } > "$fenced_refusal"
assert "the fenced copy still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$fenced_refusal")"
assert "…and carries exactly one fence marker" \
  "$([ "$(grep -c '^```' "$fenced_refusal")" -eq 1 ] && echo 0 || echo 1)"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$fenced_refusal"
expect "one prepended fence on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

trailing_refusal="$TMP/refusal-trailing-fence.md"
{ cat "$REFUSAL"; printf '```\n'; } > "$trailing_refusal"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$trailing_refusal"
expect "an unclosed fence AFTER the refusal -> still refuses" 1

setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '~~~' 'Review limit reached.' "at $REFUSAL_HEAD")"
expect "an unbalanced tilde fence refuses just the same" 1

# The opening marker's type is carried, so a backtick fence inside a tilde block is
# content rather than a close — otherwise a nested pair drifts the count odd and the case
# above fires on an ordinary review that quotes one fence style inside another.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed $CLEAN_HEAD." \
  '~~~' \
  '```' \
  'review limit reached' \
  '```' \
  '~~~' \
  'No further comments.')"
expect "a backtick pair nested in a tilde block stays balanced -> review" 0

echo
echo "== shape 2b: an artifact that is NEITHER a review nor a refusal clears nothing =="
# THE DEFAULT-ALLOW THIS SECTION EXISTS TO PIN, and it needed no attacker: positive review
# evidence was never REQUIRED, so the classifier asked only "is this a refusal" and cleared
# everything else that named the head. The reviewer publishes exactly such an artifact on
# essentially every PR, minutes before it has read anything.
#
# The placeholder body below is RECONSTRUCTED from the vendor's published wording, not
# recorded like the two fixtures — the reviewer EDITS that comment into the review when it
# finishes, so no PR still carries one to record. The cases after it therefore drive the
# SHAPE rather than the wording: an artifact from the reviewer, naming the head, carrying
# no evidence a review completed. That shape must not clear whatever it says.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  '<!-- This is an auto-generated comment: summarize by coderabbit.ai -->' \
  '> [!NOTE]' \
  '> Currently processing new changes in this PR. This may take a few minutes, please wait...' \
  '>' \
  "> Reviewing files that changed from the base of the PR and between 6fca618a and $CLEAN_HEAD.")"
expect "the 'currently processing' placeholder -> NOT a review" 1
says   "  ...and says the reviewer has not finished" "has NOT FINISHED reviewing"

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "I have not reviewed $CLEAN_HEAD yet.")"
expect "a bot saying it has not reviewed it yet -> NOT a review" 1

# The shape itself, with nothing that reads as a refusal anywhere in it. This is the case
# the refusal table cannot catch and only required evidence can: friendly, on-topic, naming
# the head, and no claim that anybody read anything.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list. 🐰")"
expect "a reviewer artifact with no evidence of a review -> refuse" 4
says   "  ...saying what is missing, not that nothing is there" "no evidence"

# THE PASSING CONTROL for all three: the same account, the same head, one line of the
# reviewer's own evidence marker added. If this ever fails, the cases above are passing
# because nothing clears rather than because evidence is what clears.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list." \
  "No actionable comments were generated in the recent review.")"
expect "…and the same artifact WITH review evidence still clears" 0

# "I am still working" is a claim about COMPLETION, so it outranks an evidence marker
# sitting elsewhere in the same body rather than losing to it — unlike refusal PROSE,
# which loses (the section on the auto-incremental notice, below). Costs a human glance
# in the worst case; the alternative costs a merge.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Currently processing new changes in this PR." \
  "No actionable comments were generated in the recent review. Reviewed $CLEAN_HEAD.")"
expect "…but a placeholder outranks an evidence marker beside it" 1

echo
echo "== shape 3: no reviewer signal at all =="
setup "$CLEAN_HEAD"
expect "nothing on the PR -> no review, and no clearance" 3
says   "  ...and says an absent review is not a pass" "NOT a pass"

setup "$CLEAN_HEAD"; add_comment teammate "$(body_file "lgtm, ship it $CLEAN_HEAD")"
expect "only a bystander's approval -> no review" 3

setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"; add_comment coderabbitai "$CLEAN"
expect "the PR's own author cannot review it" 3

setup "$CLEAN_HEAD"; add_comment dev "$CLEAN"
expect "the implementing author's own artifact -> not independent" 3

echo
echo "== a withdrawn or unsubmitted review is not an artifact =="
setup "$CLEAN_HEAD"; add_review coderabbitai DISMISSED "$CLEAN"
expect "a DISMISSED review -> no review" 3
setup "$CLEAN_HEAD"; add_review coderabbitai PENDING "$CLEAN"
expect "a PENDING review -> no review" 3

echo
echo "== a review must be pinned to the CURRENT head =="
setup "0000000000000000000000000000000000000000"; add_comment coderabbitai "$CLEAN"
expect "a review of an earlier commit -> stale, not clear" 4
says   "  ...and says which head it wanted" "0000000000000000000000000000000000000000"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$(body_file "Looks fine to me.")"
expect "a review naming no commit at all -> unpinnable, not clear" 4

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the caller's verified head still matches -> clear" 0 --head "$CLEAN_HEAD"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the head moved since verification -> refuse" 4 --head "0000000000000000000000000000000000000000"
says   "  ...and says the head moved" "head moved"

# An abbreviated SHA is how a reviewer often names the commit; it must pin just as well,
# and a DIFFERENT commit that merely shares no prefix must not.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Reviewed ${CLEAN_HEAD:0:8} — nothing to flag.")"
expect "an abbreviated head SHA still pins" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Reviewed deadbeefdeadbeef — nothing to flag.")"
expect "some other commit does not pin" 4

echo
echo "== a later real review outranks an earlier refusal =="
# The quota resets and the reviewer comes back. Both artifacts sit on the PR; the review
# is the one that decides, or a PR could never recover from having been skipped once.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"; add_comment coderabbitai "$CLEAN"
expect "refusal then review -> clear" 0

echo
echo "== --reviewer names a reviewer the table does not know =="
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "an unknown reviewer is ignored, not trusted" 3
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "…but naming it explicitly clears" 0 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$REFUSAL"
expect "…and it is held to the same refusal table" 1 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; AUTHOR="dev"; add_comment dev "$CLEAN"
expect "…and may never be the PR's own author" 2 --reviewer dev
says   "  ...saying why" "cannot be"

echo
echo "== a crafted comment cannot forge an artifact =="
# The record separator between artifacts is 16 random bytes per run, precisely because
# artifact bodies are attacker-writable. A body that tries to open a second record with a
# guessed sentinel must be inert.
setup "$CLEAN_HEAD"
add_comment teammate "$(body_file \
  "nice work" \
  "$(printf 'okf-SEPARATOR\treview\tcoderabbitai\tAPPROVED')" \
  "Reviewed $CLEAN_HEAD, no actionable comments.")"
expect "a forged record header in a comment body -> still no review" 3

echo
echo "== --match-check: which required checks belong to a reviewer =="
match() { # <name> <expected-rc>
  local rc; "$SCRIPT" --match-check "$1" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$2" ]; then printf '  PASS  %-58s (rc=%s)\n' "--match-check '$1'" "$rc"; pass=$((pass+1))
  else printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "--match-check '$1'" "$2" "$rc"; fail=$((fail+1)); fi
}
match "CodeRabbit"              0
match "coderabbitai"            0
match "Sourcery review"         0
match "Build, Lint & Format"    1
match "Unit Tests (vitest)"     1
match "review"                  1   # a CI job merely called "review" is not a reviewer

# ...and the third answer, which is the one that was missing. A check named for a code
# reviewer the table does not carry used to be indistinguishable from CI, so it was
# settled on its green bucket — the original incident, with a different vendor's name on
# it. It is now UNKNOWN, and the caller must refuse. The `1`s above and below are the
# control: this must not become a catch-all that reads every CI job as a reviewer.
match "Cursor Bugbot"           3
match "Copilot code review"     3
match "Devin Review"            3
match "AI Code Review"          3
match "review-app deploy"       1   # a Heroku-style review app is a deploy, not a review
match "Review Docs"             1

# THE OMISSION THIS BLOCK EXISTS TO CATCH. Asserting a list of spellings that already
# match cannot fail for the reason that matters — a vendor nobody added. These four ship
# today and all four classified as plain CI: three because the product's name carries no
# "review" at all, one because a word sat between the vendor and it.
match "CodeAnt AI"                    3
match "Korbit AI"                     3
match "Cursor Bug Bot"                3
match "Copilot pull request review"   3
match "Gemini Code Assist review"     3

# ...and the SHAPE, which is what survives the next vendor launch. None of these names
# exists; each is a plausible check name for a code reviewer, and each must be unknown
# rather than CI. A table of spellings passes the block above and fails this one.
for made_up in "Frobnicator AI review" "Acme PR review" "Widget pull request review" \
               "Nitpicker code review" "Zorp Review Bot" "Quux automated code review" \
               "Splunge bugbot"; do
  match "$made_up"              3
done

# The other half of the shape, and the reason it is not a catch-all: an ordinary CI job
# whose name merely contains one of those words stays CI. Widen the rows above until one
# of these turns 3 and a repo has to rename a passing check to merge.
for ci_job in "Deploy preview" "Review Docs" "docs-review-links" "release-review-notes" \
              "Preview Deploy" "code-coverage" "reviewdog-lint-report"; do
  match "$ci_job"               1
done

echo
echo "== --self-test proves the script RUNS, which the executable bit does not =="
# required-checks.sh cannot trust `[ -x ]`: a dead shebang, a syntax error, a zero-byte
# file and a truncated copy all carry the mode bit and then fail every call, which reads
# as "no required check is a reviewer's" and clears an unreviewed PR. So it asks for this
# proof instead. The exact string is the contract between the two files.
st_out="$("$SCRIPT" --self-test 2>&1)"; st_rc=$?
assert "--self-test exits 0"                    "$([ "$st_rc" -eq 0 ] && echo 0 || echo 1)"
assert "…and prints the agreed sentinel"        "$([ "$st_out" = "review-clearance: self-test ok" ] && echo 0 || echo 1)"
"$SCRIPT" --self-test extra >/dev/null 2>&1; st_rc=$?
assert "…and takes no arguments"                "$([ "$st_rc" -eq 2 ] && echo 0 || echo 1)"

echo
echo "== ...and that it is COMPLETE, which running does not prove =="
# THE HOLE THIS SECTION EXISTS TO PIN, and it was found by sweeping rather than by
# reading: the self-test sits near the TOP of the script, so a copy truncated anywhere
# BELOW it still parses, still reaches that exit, and still prints the sentinel while
# every table and the whole classifier are missing. Swept over the previous version, 112
# of its 606 truncation points passed the self-test and 109 of those went on to CLEAR an
# unreviewed PR. The old truncation case cut at `head -c 400` — inside the header comment
# — so it could not see the class at all.
#
# The sweep is every cut point from the self-test's own block to the end, which is exactly
# the range the old proof was blind to. A cut is a pass only if --self-test exits 0 AND
# prints the sentinel, which is precisely what required-checks.sh believes.
SELFTEST_LINE="$(grep -n -- '--self-test" \]; then' "$SCRIPT" | head -1 | cut -d: -f1)"
TOTAL_LINES="$(wc -l < "$SCRIPT" | tr -d ' ')"
assert "the self-test block is found, and is not the whole file" \
  "$([ -n "$SELFTEST_LINE" ] && [ "$SELFTEST_LINE" -lt "$TOTAL_LINES" ] && echo 0 || echo 1)"

TRUNC="$TMP/trunc.sh"; survivors=0; swept=0
cut_at="$SELFTEST_LINE"
while [ "$cut_at" -lt "$TOTAL_LINES" ]; do
  head -n "$cut_at" "$SCRIPT" > "$TRUNC"; chmod +x "$TRUNC"
  swept=$((swept + 1))
  out="$("$TRUNC" --self-test </dev/null 2>/dev/null)"
  [ "$?" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && {
    survivors=$((survivors + 1)); [ "$survivors" -le 3 ] && printf '        survived cut at line %s\n' "$cut_at"; }
  cut_at=$((cut_at + 1))
done
printf '  ..... swept %s truncation points from line %s to %s\n' "$swept" "$SELFTEST_LINE" "$TOTAL_LINES"
assert "the sweep actually cut somewhere (>= 100 points)" \
  "$([ "$swept" -ge 100 ] && echo 0 || echo 1)"
assert "NO truncated copy passes --self-test"             "$([ "$survivors" -eq 0 ] && echo 0 || echo 1)"

# Byte-level cuts too: a copy interrupted mid-line is the shape a half-written install or
# a full disk actually produces, and it can leave a syntactically valid file.
BYTES="$(wc -c < "$SCRIPT" | tr -d ' ')"
byte_survivors=0
for frac in 55 65 70 75 80 85 90 95 99; do
  head -c "$((BYTES * frac / 100))" "$SCRIPT" > "$TRUNC"; chmod +x "$TRUNC"
  out="$("$TRUNC" --self-test </dev/null 2>/dev/null)"
  [ "$?" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && byte_survivors=$((byte_survivors + 1))
done
assert "nor does a copy cut mid-line at nine byte offsets" \
  "$([ "$byte_survivors" -eq 0 ] && echo 0 || echo 1)"

# THE CONTROL, and the reason the sweep is not vacuous: a BYTE-FOR-BYTE copy of the same
# file, at the same path shape, self-tests fine. So the refusals above are the truncation.
cp "$SCRIPT" "$TRUNC"; chmod +x "$TRUNC"
out="$("$TRUNC" --self-test 2>&1)"; st_rc=$?
assert "…while a whole copy of the same file passes" \
  "$([ "$st_rc" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && echo 0 || echo 1)"

echo
echo "== one malformed pattern must not silently disable a whole table =="
# `hits()` read grep's OUTPUT and never its STATUS, and grep says 1 for "nothing matched"
# and 2 for "that is not a regular expression". Conflated, one typo'd row turned the
# entire refusal table off — every refusal then read as a review. Each case corrupts ONE
# row of one table in a copy of the script and asserts the copy REFUSES rather than
# proceeding with a table that cannot fire.
break_row() { # <name> <sed expression that corrupts a row> [args to the script...]
  local name="$1" expr="$2"; shift 2
  local broken="$TMP/broken.$((b_n = ${b_n:-0} + 1)).sh"
  sed "$expr" "$SCRIPT" > "$broken"; chmod +x "$broken"
  setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"; write_pr
  local out rc
  out="$("$broken" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -Fq "not valid POSIX ERE"; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=2 + the ERE complaint, got rc=%s: %s\n' \
      "$name" "$rc" "$(printf '%s' "$out" | head -2 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}
break_row "a broken REFUSALS row -> refuse, never read it as a review" \
  's/^review limit reached$/review limit reache[d/'
break_row "a broken sentinel row -> refuse"        's/^rate\.limited by .*$/rate.limited by [a-z/'
break_row "a broken REVIEWED row -> refuse"        's/^walkthrough_start$/walkthrough_start(/'
break_row "a broken NOT_YET row -> refuse"         's/^queued for review$/queued for review[/'
break_row "a broken REVIEWERS login -> refuse"     's/^coderabbitai  /coderabbitai[   /'

# ...and the same corruption is caught by the two table-only modes, so a caller that only
# ever runs those still refuses rather than settling a reviewer's check on its bucket.
BROKEN_TBL="$TMP/broken-suspect.sh"
sed 's/^code.*review$/code[^a-z0-9]*review[/' "$SCRIPT" > "$BROKEN_TBL"
chmod +x "$BROKEN_TBL"
"$BROKEN_TBL" --match-check "Build" >/dev/null 2>&1; rc=$?
assert "--match-check on a broken table -> 2, not 'it is CI'" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
"$BROKEN_TBL" --self-test >/dev/null 2>&1; rc=$?
assert "--self-test on a broken table -> 2, so the caller refuses" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
# The control: the identical sed with a VALID replacement leaves everything working.
OK_TBL="$TMP/ok-suspect.sh"
sed 's/^code.*review$/code[^a-z0-9]*reviews?/' "$SCRIPT" > "$OK_TBL"; chmod +x "$OK_TBL"
"$OK_TBL" --self-test >/dev/null 2>&1; rc=$?
assert "…while a valid edit to the same row still self-tests" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

echo
echo "== --for-check: one vendor's review may not clear another's check =="
# Two reviewers on one repo, one of them rate-limited. Unscoped, "is there a review on
# this PR" is answered by whichever reviewer did look — so the refusing vendor's required
# check clears on the other vendor's work. --for-check resolves the check name to the
# reviewer that owns it and reads only that account.
two_reviewers() {
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$REFUSAL"      # the rate-limited one
  add_comment sourcery-ai  "$CLEAN"        # the one that actually reviewed
}
two_reviewers; expect "unscoped, ANY reviewer's review answers (the bypass)" 0
two_reviewers; expect "…but the refusing vendor's own check does not clear" 1 --for-check "CodeRabbit"
says   "  ...quoting the vendor that refused" "coderabbitai"
two_reviewers; expect "…while the vendor that reviewed clears its own"     0 --for-check "Sourcery review"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "a check no reviewer owns -> refuse, never widen to everybody" 2 --for-check "Build"
says   "  ...saying whose review would clear it is unknown" "is unknown"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "--for-check and --reviewer both name a reviewer -> usage error" 2 \
  --for-check "CodeRabbit" --reviewer coderabbitai

echo
echo "== a notice about what was NOT done does not unmake a review that was =="
# Measured on this repository: 10 of its 20 reviewed PRs carry a real review comment
# whose header says "Review skipped — Auto incremental reviews are disabled", because
# .coderabbit.yaml sets auto_incremental_review: false here. Matching refusal prose over
# the whole body reads those as refusals and quotes the wrong reason at the operator.
skip_notice=(
  '> [!IMPORTANT]'
  '> ## Review skipped'
  '>'
  '> Auto incremental reviews are disabled on this repository.'
  ''
  '<!-- walkthrough_start -->'
  '## Walkthrough'
  ''
)
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]}" \
  "Reviewed between 6fca618a and $CLEAN_HEAD. **Actionable comments posted: 3**")"
expect "refusal prose beside real review evidence -> a review" 0

# ...and the same notice with NOTHING evidencing a review is still a refusal. This is the
# control: the narrowing above must key on the evidence, not on the word "skipped".
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]:0:4}" "at $CLEAN_HEAD")"
expect "…the same notice with no review evidence -> still a refusal" 1

# The hole this narrowing must not open, asserted on the evidence rather than trusted:
# the recorded refusal quotes the PR head, so if review evidence could outrank the
# machine sentinel, #30 would clear. It carries none, and the sentinel outranks anyway.
assert "the recorded refusal carries NO review-evidence marker" \
  "$(yes_if bash -c '! grep -Eqi "walkthrough_start|actionable comments" "$1"' _ "$REFUSAL")"
assert "…and does carry the machine-readable rate-limit sentinel" \
  "$(yes_if grep -Fq "rate limited by coderabbit.ai" "$REFUSAL")"
setup "$REFUSAL_HEAD"
{ cat "$REFUSAL"; printf '\n<!-- walkthrough_start -->\nActionable comments posted: 2\n'; } \
  > "$TMP/refusal-with-evidence.md"
add_comment coderabbitai "$TMP/refusal-with-evidence.md"
expect "the sentinel outranks review evidence -> still a refusal" 1

echo
echo "== a verdict that QUOTES refusal language is not itself a refusal =="
# The fallback reviewer's job on a rate-limited PR is to SAY the hosted reviewer refused
# — quoting the words, and the sentinel. Prose alone classifies that verdict as a refusal,
# which is the reviewer disqualifying its own review. The okf-verdict trailer (SCHEMA.md)
# is the structured self-declaration that settles it, and it outranks every refusal row.
VERDICT_PROSE=(
  "CodeRabbit published a green check whose body reads Review limit reached, and the"
  "comment carries the rate limited by coderabbit.ai sentinel — so no review happened."
)
trailer() { # [head_sha to claim] — the trailer SCHEMA.md defines
  printf '%s\n' '<!-- okf-verdict v1' 'verdict: changes-requested' 'reviewer: qa-reviewer' \
    "head_sha: ${1:-$CLEAN_HEAD}" 'lenses: correctness=done security=done repro=done' \
    'unverified_criteria: none' 'caveats: none' '-->'
}
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "$(trailer)")"
expect "a verdict quoting a refusal in prose -> a review" 0 --reviewer qa-bot

# The control, and it is the whole reason the guard is a TRAILER rather than a mood: the
# identical prose WITHOUT the trailer is still read as a refusal.
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "I reviewed $CLEAN_HEAD myself.")"
expect "…the same prose with no trailer -> classified as a refusal" 1 --reviewer qa-bot

echo
echo "== the trailer is PARSED, not grepped: a substring must not outrank anything =="
# The bypass this section pins. The trailer was one row of a table matched as a substring
# ANYWHERE in a body, and it outranked the vendor's own machine-readable refusal sentinel.
# So a single appended line — nineteen characters, no fields, no structure — turned the
# verbatim recorded refusal from rc=1 into rc=0. The string ships in this repo's own diff,
# and a reviewer that quotes a diff quotes the string.
one_liner="$TMP/refusal-plus-trailer-substring.md"
{ cat "$REFUSAL"; printf '\n<!-- okf-verdict v1 -->\n'; } > "$one_liner"
assert "the crafted body still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$one_liner")"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$one_liner"
expect "one appended okf-verdict substring on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

# A WELL-FORMED trailer, from the vendor's own account, must not clear either: the tier is
# scoped to a reviewer named with --reviewer, which is how the fallback reviewer is reached
# and is never how a hosted vendor is. Without the scope, anyone able to comment as the
# vendor — or any diff the vendor quotes — outranks the vendor's own refusal.
full="$TMP/refusal-plus-full-trailer.md"
{ cat "$REFUSAL"; printf '\n'; trailer "$REFUSAL_HEAD"; } > "$full"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$full"
expect "a well-formed trailer from a TABLE-matched vendor -> still refuses" 1

# ...and the control for both: the same well-formed trailer, at this head, from the
# reviewer the caller named, is a review. So the refusals above are the scoping and the
# parsing, not the trailer having stopped working.
setup "$REFUSAL_HEAD"; add_comment qa-bot "$full"
expect "…while the named fallback reviewer's own trailer clears" 0 --reviewer qa-bot

# Each required field, one at a time. A trailer missing any of them cannot be evaluated
# against SCHEMA.md's predicate at all, so it is not a structured claim — it is a comment.
malformed() { # <name> <sed expression applied to the trailer>
  local body; body="$TMP/verdict.$((v_n = ${v_n:-0} + 1)).md"
  { printf '%s\n' "${VERDICT_PROSE[@]}"; trailer | sed "$2"; } > "$body"
  setup "$CLEAN_HEAD"; add_comment qa-bot "$body"
  expect "$1" 1 --reviewer qa-bot
}
malformed "a trailer with no head_sha -> not a verdict"        '/^head_sha:/d'
malformed "a trailer for a DIFFERENT head -> not this head's"  's/^head_sha: .*/head_sha: 0123456789abcdef0123456789abcdef01234567/'
malformed "a trailer with no verdict field -> not a verdict"   '/^verdict:/d'
malformed "a trailer with no reviewer field -> not a verdict"  '/^reviewer:/d'
malformed "a trailer nobody closed -> not a block"             '/^-->/d'
malformed "a verdict value nobody defines -> not a verdict"    's/^verdict: .*/verdict: fine-i-guess/'
# The marker has to be a line, not a phrase inside one — otherwise the block opener is
# whatever prose happens to mention it.
malformed "the marker buried in a sentence -> not a block"     's/^<!-- okf-verdict v1$/as in <!-- okf-verdict v1 -- see SCHEMA.md/'

echo
echo "== the environment failing is never a clearance =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; : > "$FIX/gh_broken"
expect "PR unreadable -> refuse, and not as 'no review'" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; : > "$FIX/jq_broken"
expect "the JSON reader cannot answer -> refuse" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "unknown option -> usage error" 2 --nope
rc=0; "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert "no arguments -> usage error" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
