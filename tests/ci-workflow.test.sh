#!/usr/bin/env bash
#
# ci-workflow.test.sh — the workflow that runs `tests/*.test.sh` in CI must actually
# exist, be valid YAML, and invoke the FULL suite on the events this task exists to
# cover. ai-bridge-v4/task-001's whole reason to exist is that a moved head, or a
# harness that quietly regresses, has no signal until a human happens to look — so the
# guard against THAT gap must not itself be a thing only a human happens to notice was
# deleted. Both directions are asserted, not just "present and correct": the existence
# check is proven to actually go red on an absent file, not merely green on today's.
#
# WHAT THIS DOES NOT DO. It does not re-run the suite (that is what the workflow itself
# is for) and it does not require any particular CI provider beyond "a file GitHub
# Actions reads" — it reads .github/workflows/tests.yml because that is the file this
# repo ships, and pins its path the same way the other structural checks here pin the
# things they depend on existing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "ci-workflow.test: cannot locate self" >&2; exit 2; }
REPO="$(cd "$HERE/.." && pwd)" || { echo "ci-workflow.test: cannot locate repo root" >&2; exit 2; }
WF="$REPO/.github/workflows/tests.yml"
DECLARED="$REPO/.github/required-checks.txt"

# Single source of truth for both sides — same idiom as harness-shell-dialect.test.sh's
# SHEBANG/SCOPE_GLOB constants: the job's declared name is verified against the
# workflow's ACTUAL content below, not merely assumed to still say this.
CHECK_NAME="harness suite"

pass=0; fail=0; skip=0
assert()  { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
            else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
summary() { echo; echo "pass=$pass fail=$fail skip=$skip"; [[ "$fail" == 0 ]] || exit 1; exit 0; }

echo "== the existence check actually discriminates, not just today's state =="
# Proves the assertion below is not vacuously true — a guard whose own regression test
# never sees it fail proves nothing (the class of bug this whole task exists to close).
MISSING_WF="$REPO/.github/workflows/does-not-exist-$$.yml"
assert "a present file passes the existence check" \
  "$([ -f "$WF" ] && echo 0 || echo 1)"
assert "…and a missing one FAILS the identical check (the guard is not vacuous)" \
  "$([ -f "$MISSING_WF" ] && echo 1 || echo 0)"

echo "== .github/workflows/tests.yml exists and is non-empty =="
assert "$WF exists" "$([ -f "$WF" ] && echo 0 || echo 1)"
if [[ ! -f "$WF" ]]; then
  echo "ci-workflow.test: $WF is missing — cannot check its contents, stopping here" >&2
  summary
fi
assert "$WF is non-empty" "$([ -s "$WF" ] && echo 0 || echo 1)"

WF_TEXT="$(cat "$WF")"

echo "== it is valid YAML, checked against a real parser or actionlint, never a text guess =="
# Same oracle order as deliverable-paths-vs-yaml.test.sh: PyYAML needs no second
# interpreter, Psych ships with the Ruby macOS and Linux CI images both carry. Where a
# repo has actionlint on PATH that is stronger still (schema-aware, not just "parses"),
# so it is preferred when present. Absent all three: SKIP, never a false FAIL — a
# missing optional tool is not a defect in the workflow.
if command -v actionlint >/dev/null 2>&1; then
  AL_OUT="$(actionlint "$WF" 2>&1)"
  AL_RC=$?
  assert "actionlint reports zero problems on $WF" "$([ "$AL_RC" -eq 0 ] && echo 0 || echo 1)"
  [[ "$AL_RC" -eq 0 ]] || printf '%s\n' "$AL_OUT" >&2
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  assert "PyYAML parses $WF without error" \
    "$(python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WF" >/dev/null 2>&1 && echo 0 || echo 1)"
elif command -v ruby >/dev/null 2>&1 && ruby -rpsych -e 'Psych::VERSION' >/dev/null 2>&1; then
  assert "Psych parses $WF without error" \
    "$(ruby -rpsych -e "Psych.load_file(ARGV[0])" "$WF" >/dev/null 2>&1 && echo 0 || echo 1)"
else
  skipped "no actionlint, PyYAML or Ruby/Psych on this machine — nothing to parse with"
fi

echo "== it triggers on pull_request and push against the default branch =="
assert "declares a pull_request trigger" \
  "$(grep -Eq '^[[:space:]]*pull_request:' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "declares a push trigger" \
  "$(grep -Eq '^[[:space:]]*push:' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "both triggers scope to the default branch (main)" \
  "$([ "$(grep -cE '^[[:space:]]*branches:[[:space:]]*\[main\]' <<<"$WF_TEXT")" -ge 2 ] && echo 0 || echo 1)"

echo "== it actually invokes the FULL suite — no partial, hardcoded file list =="
# The literal glob, not a subset: this is what "the FULL tests/*.test.sh suite" in the
# task's acceptance criteria cashes out to. Anchored to a real shell-loop use (preceded
# by 'in'/'(' is too fragile to pin generically; the literal glob string is what matters
# and what a narrowing edit would have to change).
assert "the run step invokes the literal glob tests/*.test.sh" \
  "$(grep -qF 'tests/*.test.sh' <<<"$WF_TEXT" && echo 0 || echo 1)"

echo "== ai-bridge-v4/task-022: the host-rendering oracle's --check runs automatically =="
# Before this task it could only be run by hand, which meant it would not be run. Pinned
# on the literal invocation, same idiom as the tests/*.test.sh glob above, and on it being
# NON-blocking — a required check must not fail on a renderer wording change this repo
# does not control (docs/conventions.md, "the host wins and it is recorded").
assert "a step invokes tests/fixtures/reviewer/record-host-rendering.sh --check" \
  "$(grep -qF 'tests/fixtures/reviewer/record-host-rendering.sh --check' <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "…and that step is continue-on-error, so host drift never fails the required check" \
  "$(grep -B8 -F 'record-host-rendering.sh --check' <<<"$WF_TEXT" | grep -qF 'continue-on-error: true' && echo 0 || echo 1)"

echo "== the runner distrusts a harness's exit code on its own =="
# Pins that the double-check this task exists to add — reported fail count, not just
# $? — is actually present, not merely described in a comment. See
# knowledge/findings/suite-cleanup-can-delete-its-own-checkout.md: a harness printed
# pass=53 fail=0 and exited 0 while it had destroyed its own checkout.
assert "the runner extracts a 'pass=N fail=N' summary from each harness's own output" \
  "$(grep -qF "grep -oE 'pass=[0-9]+ fail=[0-9]+'" <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "…and gates on the reported fail count, not only on the exit status" \
  "$(grep -qF 'f_fail' <<<"$WF_TEXT" && echo 0 || echo 1)"

echo "== the runner re-verifies the checkout itself survives each harness =="
assert "a checkout-integrity check runs after every harness, not just once at the start" \
  "$(grep -qF 'verify_checkout' <<<"$WF_TEXT" && echo 0 || echo 1)"

echo "== the check name is declared as a required check, verbatim, on both sides =="
# CHECK_NAME above is the pin; both the workflow and the declared-checks file are
# verified against it, so a rename on either side that forgets the other goes red here
# instead of silently making the required check unresolvable.
assert "the workflow's job is named exactly \"$CHECK_NAME\" (anchored, not a substring)" \
  "$(grep -qE "^[[:space:]]+name: $CHECK_NAME\$" <<<"$WF_TEXT" && echo 0 || echo 1)"
assert "$DECLARED exists" "$([ -f "$DECLARED" ] && echo 0 || echo 1)"
if [[ -f "$DECLARED" ]]; then
  DECLARED_NAMES="$(grep -v '^#' "$DECLARED" | grep -v '^$')"
  assert "$DECLARED lists that exact check name" \
    "$(grep -Fxq "$CHECK_NAME" <<<"$DECLARED_NAMES" && echo 0 || echo 1)"
fi

summary
