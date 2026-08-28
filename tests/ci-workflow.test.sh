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

echo "== the runner treats a MISSING pass/fail summary as a FAILURE, never a pass =="
# ai-bridge-v4/task-031, criterion 4. Every assertion above this one reads the
# WORKFLOW'S TEXT — a grep can drift from what the embedded shell actually does with
# it. This section extracts the "Run tests/*.test.sh" step's `run:` script VERBATIM
# and executes it for real, against a fixture harness that exits non-zero printing
# NOTHING — exactly tests/snapshot.test.sh's failure mode under install.sh's worktree
# guard before task-031's fix, and "the half that outlives this one harness" the task
# doc names: a harness that dies before printing its summary must be indistinguishable
# from a FAILURE, never from a pass, no matter which harness it is.
if python3 -c 'import yaml' >/dev/null 2>&1; then RUNNER_ORACLE="pyyaml"
elif command -v ruby >/dev/null 2>&1 && ruby -rpsych -e 'Psych::VERSION' >/dev/null 2>&1; then RUNNER_ORACLE="psych"
else RUNNER_ORACLE=""
fi

if [ -z "$RUNNER_ORACLE" ]; then
  skipped "no YAML parser on this machine (PyYAML or Ruby/Psych) — cannot extract the runner's embedded script"
else
  RUNNER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-workflow-runner.XXXXXX")" || {
    echo "ci-workflow.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
  trap 'rm -rf "$RUNNER_TMP"' EXIT

  EXTRACTED="$RUNNER_TMP/runner.sh"
  if [ "$RUNNER_ORACLE" = "pyyaml" ]; then
    python3 - "$WF" > "$EXTRACTED" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["suite"]["steps"]
step = next((s for s in steps if s.get("name") == "Run tests/*.test.sh"), None)
if step is None:
    sys.exit("step not found")
sys.stdout.write(step["run"])
PY
  else
    ruby -rpsych - "$WF" > "$EXTRACTED" <<'RB'
require "psych"
wf = Psych.load_file(ARGV[0])
steps = wf["jobs"]["suite"]["steps"]
step = steps.find { |s| s["name"] == "Run tests/*.test.sh" }
abort("step not found") unless step
print step["run"]
RB
  fi
  assert "the run step's script was extracted from $WF" \
    "$([ -s "$EXTRACTED" ] && echo 0 || echo 1)"

  # A minimal workspace covering the extracted script's own preconditions: a git repo
  # with a commit (verify_checkout reads HEAD), and tests/ + symlink/ present. ONE
  # fixture harness, printing nothing and exiting non-zero.
  WS="$RUNNER_TMP/ws"
  mkdir -p "$WS/tests" "$WS/symlink"
  ( cd "$WS" && git init -q . && git config user.email t@e.st && git config user.name t \
    && : > .keep && git add .keep && git commit -qm seed >/dev/null )
  cat > "$WS/tests/silent-death.test.sh" <<'FIX'
#!/usr/bin/env bash
exit 7
FIX

  RUN_OUT="$( cd "$WS" && GITHUB_WORKSPACE="$WS" RUNNER_TEMP="$RUNNER_TMP/runner-tmp" bash "$EXTRACTED" 2>&1 )"; RUN_RC=$?
  assert "a harness with no summary and a non-zero exit fails the runner" \
    "$([ "$RUN_RC" -ne 0 ] && echo 0 || echo 1)"
  assert "…and says so by name" \
    "$(printf '%s\n' "$RUN_OUT" | grep -qF 'printed no recognised pass/fail summary' && echo 0 || echo 1)"
  assert "…lists it under FAILED harnesses" \
    "$(printf '%s\n' "$RUN_OUT" | grep -qF 'FAILED harnesses:' && echo 0 || echo 1)"
  assert "…and never prints the all-passed banner" \
    "$(printf '%s\n' "$RUN_OUT" | grep -qF 'ok: all' && echo 1 || echo 0)"

  # PROVING THE PIN IS NOT VACUOUS. Every assertion above passed on the FIRST run,
  # with nothing broken to make it fail — the runner already gets this right. So the
  # non-vacuity is shown the other way: mutate the runner's OWN missing-summary guard
  # into the naive shape the task doc warns about ("a harness that dies before
  # printing is indistinguishable from one that never ran") by replacing it with a
  # bare `continue`, which skips both the exit-code check below it AND recording the
  # harness as bad, then confirm THAT version reports a false all-clear on the
  # identical fixture.
  MUTATED="$RUNNER_TMP/runner-mutated.sh"
  # Mirrors the extraction branch above: on a Python-less host RUNNER_ORACLE is
  # "psych", and a bare python3 call here would die under this file's own
  # `set -uo pipefail` before the assertion below it ever ran — the branch built
  # specifically for that host would never reach what it exists to prove.
  #
  # ANCHORED ON THE UNIQUE ERROR TEXT, not a generic "if -z summary" pattern: the
  # real script has TWO such blocks (an inner one that only swaps the dense summary
  # for the prose-style fallback, and this outer one that actually gives up). A
  # generic pattern matches both, and Python's `subn(..., count=1)` silently caps
  # the reported match count at 1 regardless of how many exist — hiding exactly the
  # ambiguity this guard is supposed to catch. Anchoring on the error message text,
  # unique to the give-up block, then walking outward to its enclosing `if`/`fi` is
  # unambiguous regardless of how many other "if -z summary" blocks the script has.
  if [ "$RUNNER_ORACLE" = "pyyaml" ]; then
    python3 - "$EXTRACTED" "$MUTATED" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
anchor = "printed no recognised pass/fail summary"
idx = src.index(anchor)
if_re = re.compile(r'if \[ -z "\$summary" \]; then\n')
starts = [m.end() for m in if_re.finditer(src) if m.start() < idx]
if not starts:
    sys.exit("could not locate the enclosing missing-summary guard")
then_end = starts[-1]
fi_m = re.compile(r'\n( *)fi\n').search(src, idx)
if not fi_m:
    sys.exit("could not find the closing fi for the missing-summary guard")
mutated = src[:then_end] + "      continue\n" + fi_m.group(1) + "fi\n" + src[fi_m.end():]
open(sys.argv[2], "w").write(mutated)
PY
  else
    ruby - "$EXTRACTED" "$MUTATED" <<'RB'
src = File.read(ARGV[0])
anchor = "printed no recognised pass/fail summary"
idx = src.index(anchor)
abort("could not locate the missing-summary anchor text") unless idx
if_re = /if \[ -z "\$summary" \]; then\n/
if_starts = []
pos = 0
while (m = if_re.match(src, pos))
  if_starts << m.end(0)
  pos = m.end(0)
end
if_starts.select! { |e| e <= idx }
abort("could not locate the enclosing missing-summary guard") if if_starts.empty?
then_end = if_starts.last
fi_match = /\n( *)fi\n/.match(src, idx)
abort("could not find the closing fi for the missing-summary guard") unless fi_match
mutated = src[0...then_end] + "      continue\n" + fi_match[1] + "fi\n" + src[fi_match.end(0)..-1]
File.write(ARGV[1], mutated)
RB
  fi
  MUT_STATUS=$?
  assert "the give-up missing-summary guard was located and mutated" "$([ "$MUT_STATUS" -eq 0 ] && echo 0 || echo 1)"
  if [ "$MUT_STATUS" -eq 0 ]; then
    MUT_OUT="$( cd "$WS" && GITHUB_WORKSPACE="$WS" RUNNER_TEMP="$RUNNER_TMP/runner-tmp2" bash "$MUTATED" 2>&1 )"; MUT_RC=$?
    assert "…and on the SAME fixture, a mutated runner that drops the guard falsely passes (proves the pin bites)" \
      "$([ "$MUT_RC" -eq 0 ] && echo 0 || echo 1)"
    assert "…reporting the all-clear banner it should not" \
      "$(printf '%s\n' "$MUT_OUT" | grep -qF 'ok: all' && echo 0 || echo 1)"
  fi
fi

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
