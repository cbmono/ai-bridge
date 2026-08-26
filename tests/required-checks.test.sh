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
fi

# The two scripts ship as one unit. Without the sibling, this one cannot tell a
# reviewer's check from a CI job — an unknown reviewer state, which must refuse.
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

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
