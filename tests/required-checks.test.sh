#!/usr/bin/env bash
# Exercises the delegated merge gate's precondition 1 — symlink/scripts/required-checks.sh.
#
# `gh` is replaced by a stub on PATH that answers from fixture files, so the whole
# matrix runs offline: platform-required sets, the declared-list fallback, and every
# way both are supposed to REFUSE. The refusals are the point — this gate is the only
# thing standing between an autonomous loop and a merge, so the tests that matter most
# are the ones proving it fails closed.
#
# The last section covers the one green check that means nothing: a REQUIRED check that
# belongs to a hosted reviewer. A reviewer that declines to review still exits
# successfully, so its check reports `pass` exactly as a reviewed PR's does — which is
# how two PRs merged unreviewed. That name is handed to review-clearance.sh instead of
# being settled by its bucket, and the cases here pin both directions: a real recorded
# review clears, the recorded refusal does not, and an unreadable reviewer state refuses
# rather than falling through.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/symlink/scripts/required-checks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- gh stub -----------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for required-checks.sh. Answers from $FIX; absent fixture = absent thing.
has() { local n="$1"; shift; for a in "$@"; do [ "$a" = "$n" ] && return 0; done; return 1; }

case "${1:-}" in
  pr)
    case "${2:-}" in
      view)
        # Two different `pr view` calls now reach this stub: required-checks.sh asks for
        # a TSV of PR facts, review-clearance.sh asks for the artifacts as JSON. Branch
        # on the field list, not on argument position.
        if printf '%s\n' "$@" | grep -q comments; then
          [ -f "$FIX/pr_json" ] || { echo "no PR" >&2; exit 1; }
          cat "$FIX/pr_json"
        else
          [ -f "$FIX/pr_meta" ] || { echo "no PR" >&2; exit 1; }
          cat "$FIX/pr_meta"
        fi ;;
      checks)
        if has --required "$@"; then
          if [ -f "$FIX/platform_broken" ]; then
            # A transient failure. Real gh puts errors on stderr, same as the
            # no-required message — which is exactly why the two can't be told
            # apart by stream or exit code, only by text.
            echo "error connecting to api.github.com" >&2; exit 1
          elif [ -f "$FIX/platform_garbage" ]; then
            # Some other message entirely — a reworded gh, a proxy page, anything.
            echo "could not resolve to a Repository" >&2; exit 1
          elif [ -f "$FIX/platform_empty" ]; then
            if has --jq "$@"; then :; else echo '[]'; fi
          elif [ -f "$FIX/platform_names" ]; then
            if has --jq "$@"; then
              [ -f "$FIX/platform_enum_broken" ] && { echo "boom" >&2; exit 1; }
              cat "$FIX/platform_names"
            else echo '[{"name":"stub","bucket":"pass"}]'; fi
          else
            # Real gh: this goes to STDERR and exits 1 (verified against a live repo
            # with no protection). The script must not confuse it with a failing
            # required check, nor with a query that errored.
            echo "no required checks reported on the 'topic' branch" >&2; exit 1
          fi
        else
          cat "$FIX/checks" 2>/dev/null
          # Real gh exits 8 when anything is pending, 1 on failure.
          grep -qv '^pass	' "$FIX/checks" 2>/dev/null && exit 8
        fi ;;
      diff)
        [ -f "$FIX/diff_fails" ] && { echo "no diff" >&2; exit 1; }
        cat "$FIX/diff" 2>/dev/null; exit 0 ;;
      *) echo "stub: unhandled pr $2" >&2; exit 99 ;;
    esac ;;
  api)
    # Real gh prints the error BODY to stdout on a 404 and only the summary to
    # stderr — reproduce that, or the script's "did the fetch work" logic is untested.
    [ -f "$FIX/declared" ] || {
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    }
    cat "$FIX/declared" ;;
  *) echo "stub: unhandled $1" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

HEAD_SHA="0c2592f7bb98d3de9a7a181d1762dfcaf80785d9"

setup() { # start from: a readable PR, no protection, no declared list, no diff
  rm -rf "$FIX"; mkdir -p "$FIX"
  printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$HEAD_SHA" > "$FIX/pr_meta"
  : > "$FIX/checks"
}

checks() { printf '%s\n' "$@" > "$FIX/checks"; }        # each arg: "bucket<TAB>name"
declared() { printf '%s\n' "$@" > "$FIX/declared"; }
platform() { printf '%s\n' "$@" > "$FIX/platform_names"; }
diff_files() { printf '%s\n' "$@" > "$FIX/diff"; }

expect() { # <name> <expected-rc> [extra args to the script...]
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(printf '%s' "$out" | head -3 | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — assert against the previous expect()'s output
  if printf '%s' "$LAST_OUT" | grep -Fq "$2"; then
    printf '  PASS  %-56s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s missing %s in: %s\n' "$1" "$2" "$(printf '%s' "$LAST_OUT" | head -2 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

echo "== required-checks gate =="

# --- nothing to enforce: the authority is not exercisable --------------------
setup; checks "pass	Build"
expect "no protection, no declared list -> not exercisable" 3
says   "  ...and says which file it looked for" "$(printf '.github/required-checks.txt')"

setup; checks "pass	Build"; declared "# only a comment" "" "   "
expect "declared list empty after parsing -> not exercisable" 3

# --- declared fallback: the happy path ---------------------------------------
setup
checks "pass	Build, Lint & Format" "pass	Unit Tests (vitest)" "pass	CodeRabbit"
declared "# what must be green before an autonomous merge" "Build, Lint & Format" "" "Unit Tests (vitest)"
expect "declared list, all green -> clear" 0
says   "  ...and reports the declared source" "source: declared"

# --- declared fallback: every way it must refuse -----------------------------
setup
checks "pass	Build, Lint & Format"
declared "Build, Lint & Format" "Unit Tests (vitest)"
expect "declared name never reported (renamed) -> refuse" 1
says   "  ...and names the drifted check" "Unit Tests (vitest): not reported"

setup; checks "fail	Build" "pass	Other"; declared "Build"
expect "declared check failing -> refuse" 1

setup; checks "pending	Build"; declared "Build"
expect "declared check pending -> refuse" 1

setup; checks "skipping	Build"; declared "Build"
expect "declared check skipped -> refuse (skipped is not passed)" 1

setup; checks "pass	Build" "fail	Build"; declared "Build"
expect "same name reported twice, one failing -> refuse" 1

# --- the gate cannot clear a PR that rewrites the gate -----------------------
setup
checks "pass	Build"; declared "Build"; diff_files "src/app.ts" ".github/required-checks.txt"
expect "PR edits the declared list -> human decision" 4

setup; checks "pass	Build"; declared "Build"; diff_files "src/app.ts" "README.md"
expect "PR touches unrelated files -> unaffected" 0

setup; checks "pass	Build"; declared "Build"; : > "$FIX/diff_fails"
expect "cannot list the PR's files -> refuse, not clear" 2

# --- platform protection wins, and is never confused with 'nothing required' --
setup
platform "Build" "E2E"
checks "pass	Build" "pass	E2E"
declared "A check nobody reports"          # would refuse if the fallback were used
expect "platform set present -> platform wins over declared" 0
says   "  ...and reports the platform source" "source: platform"

setup
platform "Build"
checks "fail	Build"
declared "Something that passes"           # must NOT rescue a failing platform check
expect "platform check failing -> refuse, no fallback to declared" 1

# An unreadable platform is NOT an unprotected one. Every case below has a declared
# list that would clear — the gate must refuse anyway, because falling back here
# would swap protection we failed to read for a list that may be weaker.
setup
: > "$FIX/platform_broken"
checks "pass	Build"; declared "Build"
expect "platform probe errors (no output) -> refuse, no fallback" 2

setup
: > "$FIX/platform_garbage"
checks "pass	Build"; declared "Build"
expect "platform probe answers something unrecognised -> refuse" 2
says   "  ...and shows what it got" "could not resolve to a Repository"

setup
platform "Build"; : > "$FIX/platform_enum_broken"
checks "pass	Build"; declared "Build"
expect "protection answered but names unreadable -> refuse" 2

# ...but an EMPTY required set is a real answer, not a failure: protection exists and
# requires nothing, so the declared list is allowed to speak.
setup
: > "$FIX/platform_empty"
checks "pass	Build"; declared "Build"
expect "protection requires nothing -> declared list may answer" 0
says   "  ...via the declared source" "source: declared"

# --- head pinning -------------------------------------------------------------
setup; checks "pass	Build"; declared "Build"
expect "head matches the verified SHA -> clear" 0 --head "$HEAD_SHA"

setup; checks "pass	Build"; declared "Build"
expect "head moved since verification -> refuse" 1 --head "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

# --- environment failures fail closed, not open -------------------------------
setup; rm -f "$FIX/pr_meta"; declared "Build"
expect "PR unreadable -> error, never a clearance" 2

setup; checks "pass	Build"; declared "Build"
expect "unknown option -> usage error" 2 --nope

# --- a required check that belongs to a REVIEWER is not settled by its bucket -
# The failure this whole section exists for: three PRs in one tick, all three with a
# green reviewer check, one reviewed and two refused — and the two refusals merged.
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer"
CR_CLEAN="$FIXTURES/clean-review.pr29.md"      # a real review, recorded verbatim
CR_REFUSAL="$FIXTURES/rate-limit-refusal.pr30.md"  # "Review limit reached", ditto
CR_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"   # the head #29 was reviewed at

if ! command -v jq >/dev/null 2>&1; then
  echo "  ..... reviewer-deferral cases skipped (jq absent; the script needs it too)"
else
  reviewer_pr() { # <body-file>|"" — the artifacts review-clearance.sh will read
    printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$CR_HEAD" > "$FIX/pr_meta"
    if [ -n "${1:-}" ]; then
      jq -n --arg h "$CR_HEAD" --rawfile b "$1" \
        '{url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
          author:{login:"dev"}, reviews:[],
          comments:[{author:{login:"coderabbitai"}, body:$b}]}' > "$FIX/pr_json"
    else
      jq -n --arg h "$CR_HEAD" \
        '{url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
          author:{login:"dev"}, reviews:[], comments:[]}' > "$FIX/pr_json"
    fi
  }

  setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
  reviewer_pr "$CR_CLEAN"
  expect "required reviewer check + a real review -> clear" 0

  setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
  reviewer_pr "$CR_REFUSAL"
  expect "required reviewer check GREEN but the reviewer refused -> refuse" 1
  says   "  ...and says a green check is not a review" "never that a review happened"
  says   "  ...and quotes the refusal" "Review limit reached"
  says   "  ...and names the reviewer-owned required check" "required, and reviewer-owned: CodeRabbit"

  setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
  reviewer_pr ""
  expect "required reviewer check green but nothing reviewed -> refuse" 1

  setup; checks "pass	Build" "pass	CodeRabbit"; declared "Build" "CodeRabbit"
  reviewer_pr "$CR_CLEAN"; rm -f "$FIX/pr_json"
  expect "reviewer state unreadable -> refuse as unknown, not as clear" 2

  # Scope: a required set with no reviewer in it never consults the reviewer at all —
  # proven by leaving the reviewer state unreadable and still clearing.
  setup; checks "pass	Build"; declared "Build"; rm -f "$FIX/pr_json"
  expect "no reviewer among the required names -> unaffected" 0

  # --- one vendor's review may not clear another vendor's check ---------------
  # Two reviewers required, one rate-limited. A single unscoped clearance call answers
  # "is there a review on this PR" and the vendor that DID review clears the vendor that
  # refused — the same substitution as the green check, one level in. Each reviewer-owned
  # name is now cleared against the reviewer that owns it.
  two_vendors() { # <coderabbit-body> <sourcery-body>
    printf 'https://github.com/acme/widgets/pull/42\tmain\t%s\n' "$CR_HEAD" > "$FIX/pr_meta"
    jq -n --arg h "$CR_HEAD" --rawfile a "$1" --rawfile b "$2" \
      '{url:"https://github.com/acme/widgets/pull/42", headRefOid:$h,
        author:{login:"dev"}, reviews:[],
        comments:[{author:{login:"coderabbitai"}, body:$a},
                  {author:{login:"sourcery-ai"},  body:$b}]}' > "$FIX/pr_json"
  }

  setup; checks "pass	Build" "pass	CodeRabbit" "pass	Sourcery review"
  declared "Build" "CodeRabbit" "Sourcery review"
  two_vendors "$CR_REFUSAL" "$CR_CLEAN"
  expect "one vendor reviewed, the other refused -> refuse" 1
  says   "  ...naming the check whose reviewer refused" "required check 'CodeRabbit'"

  setup; checks "pass	Build" "pass	CodeRabbit" "pass	Sourcery review"
  declared "Build" "CodeRabbit" "Sourcery review"
  two_vendors "$CR_CLEAN" "$CR_CLEAN"
  expect "both vendors reviewed this head -> clear" 0

  # --- a required check named for a reviewer nobody knows ---------------------
  # The original incident with a different vendor on it: `Cursor Bugbot` is green, no
  # reviewer row owns it, and it used to be settled on that bucket as if it were CI.
  setup; checks "pass	Build" "pass	Cursor Bugbot"; declared "Build" "Cursor Bugbot"
  reviewer_pr "$CR_CLEAN"
  expect "an unrecognised reviewer's check -> refuse as unknown" 2
  says   "  ...naming the check it cannot classify" "unrecognised reviewer check: Cursor Bugbot"
fi

# --- the sibling has to be there AND have to run -----------------------------
# The two scripts ship as one unit. Without the sibling, this one cannot tell a
# reviewer's check from a CI job — an unknown reviewer state, which must refuse.
#
# AND A PRESENT-BUT-BROKEN SIBLING IS THE WORSE CASE, which is what the rest of this
# section is. `[ -x ]` tests a mode bit: every variant below carries it and none of them
# runs, so every `--match-check` call fails, every required name looks like plain CI, no
# clearance is ever consulted, and the gate reports `ok: N required check(s) pass` on an
# unreviewed PR. The gate does not fail — it silently is not there. Each case therefore
# asserts BOTH the exit code and that the output is the sibling complaint, so a pass here
# cannot come from some unrelated refusal.
sibling_case() { # <name> <what to write into review-clearance.sh> <expected message>
  local name="$1" writer="$2" want="$3"
  local dir="$TMP/sib.$((sib_n = ${sib_n:-0} + 1))"; mkdir -p "$dir"
  cp "$SCRIPT" "$dir/required-checks.sh"
  eval "$writer" > "$dir/review-clearance.sh"
  chmod +x "$dir/review-clearance.sh"           # the mode bit `[ -x ]` would be happy with
  setup; checks "pass	Build"; declared "Build"
  local out rc
  out="$("$dir/required-checks.sh" 42 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -Fq "$want"; then
    printf '  PASS  %-56s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-56s expected rc=2 + %s, got rc=%s: %s\n' \
      "$name" "$want" "$rc" "$(printf '%s' "$out" | head -2 | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

LONELY="$TMP/lonely"; mkdir -p "$LONELY"
cp "$SCRIPT" "$LONELY/required-checks.sh"
setup; checks "pass	Build"; declared "Build"
out="$("$LONELY/required-checks.sh" 42 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -Fq "review-clearance.sh not found"; then
  printf '  PASS  %-56s (rc=%s)\n' "review-clearance.sh missing -> refuse, never clear" "$rc"; pass=$((pass+1))
else
  printf '  FAIL  %-56s expected rc=2 got rc=%s\n' "review-clearance.sh missing -> refuse, never clear" "$rc"
  fail=$((fail+1))
fi

BROKEN="is present but does not run"
sibling_case "zero-byte sibling -> refuse, never clear" \
  'printf ""' "$BROKEN"
sibling_case "dead shebang -> refuse, never clear" \
  'printf "#!/nonexistent/interpreter\nexit 0\n"' "$BROKEN"
sibling_case "syntax error -> refuse, never clear" \
  'printf "#!/usr/bin/env bash\nif [ 1 ; then\n"' "$BROKEN"
sibling_case "truncated in its header comment -> refuse, never clear" \
  'head -c 400 "$(dirname "$SCRIPT")/review-clearance.sh"' "$BROKEN"

# THE TRUNCATION THAT ACTUALLY GETS THROUGH, and the case above cannot show it: a cut at
# 400 bytes lands inside the sibling's header comment, so the file has no --self-test at
# all and fails for that. The dangerous cut is BELOW the self-test block — the file still
# parses, still answers the self-test, and has lost the tables and the classifier the
# answer was vouching for. Swept over the previous version, 109 such cuts went on to clear
# an unreviewed PR through this script. These four walk that range end to end.
SIB_SRC="$(dirname "$SCRIPT")/review-clearance.sh"
SIB_SELFTEST="$(grep -n -- '--self-test" \]; then' "$SIB_SRC" | head -1 | cut -d: -f1)"
SIB_LINES="$(wc -l < "$SIB_SRC" | tr -d ' ')"
for frac in 5 33 66 99; do
  cut_line=$(( SIB_SELFTEST + (SIB_LINES - SIB_SELFTEST) * frac / 100 ))
  sibling_case "cut ${frac}% past the self-test -> refuse, never clear" \
    "head -n $cut_line \"\$SIB_SRC\"" "$BROKEN"
done
# Version skew, which is the likely way this happens in a live instance rather than a
# corrupted file: a sibling from before the self-test contract answers a usage error to
# `--self-test` and works perfectly otherwise. Refuse anyway — "I cannot confirm this
# runs" is the same unknown state whether the cause is corruption or an old copy, and
# the repair (`install.sh`) is the same one.
sibling_case "a sibling too old to self-test -> refuse until relinked" \
  'printf "#!/usr/bin/env bash\n[ \"\$1\" = --match-check ] && exit 1\nexit 2\n"' \
  "$BROKEN"
# A liar is deliberately NOT tested here. A sibling that fakes the sentinel and then
# answers whatever it likes is not a failure mode this gate can detect — it is the gate,
# and anyone who can rewrite it can rewrite this file beside it. The self-test's job is
# the accidental break (truncation, syntax error, skew), which is the one that happens.
# Any answer outside {0,1,3} means the sibling is doing something this script has no
# reading for. Unknown, so refuse — rather than treating "not 0" as "not a reviewer".
sibling_case "--match-check answers an unknown code -> refuse" \
  'printf "#!/usr/bin/env bash\n[ \"\$1\" = --self-test ] && { echo \"review-clearance: self-test ok\"; exit 0; }\n[ \"\$1\" = --match-check ] && exit 7\nexit 0\n"' \
  "which is not one of"

# The passing control for the whole section: the REAL sibling, same fixture, clears. So
# the refusals above are the sibling being broken and not the fixture being unclearable.
REALSIB="$TMP/realsib"; mkdir -p "$REALSIB"
cp "$SCRIPT" "$REALSIB/required-checks.sh"
cp "$(dirname "$SCRIPT")/review-clearance.sh" "$REALSIB/review-clearance.sh"
setup; checks "pass	Build"; declared "Build"
out="$("$REALSIB/required-checks.sh" 42 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '  PASS  %-56s (rc=%s)\n' "…and an intact sibling clears the same fixture" "$rc"; pass=$((pass+1))
else
  printf '  FAIL  %-56s expected rc=0 got rc=%s: %s\n' "…and an intact sibling clears the same fixture" \
    "$rc" "$(printf '%s' "$out" | head -2 | tr '\n' '|')"
  fail=$((fail+1))
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
