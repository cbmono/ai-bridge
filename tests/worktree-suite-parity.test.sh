#!/usr/bin/env bash
#
# worktree-suite-parity.test.sh — the suite gives the SAME result from a linked git
# worktree as from the repository's main tree. Pins ai-bridge-v4/task-029.
#
# WHY THIS EXISTS. install.sh refuses, by design, to run from a linked worktree (see its
# own header and tests/installer-worktree-guard.test.sh, which owns that guard). Three
# calls in tests/board-renderers.test.sh used to hand it $TPL/install.sh unconditionally,
# so whenever $TPL itself was a worktree — which is EVERY role agent's working copy, per
# CONVENTIONS.md — the guard fired, those three calls silently stamped nothing, and nine
# downstream assertions failed for a reason that had nothing to do with whatever the
# agent actually changed. An agent that learns "some failures are always there" is an
# agent that waves the next real one through — the same shape as the vacuous
# self-skipping assertion tests/board-renderers.test.sh carried until task-024, and the
# rate-limited-review-behind-a-green-check defect from task-010.
#
# WHAT THIS PINS, TOGETHER, SO NEITHER HALF OF THE FIX CAN REGRESS ALONE:
#   1. tests/board-renderers.test.sh reports fail=0 when run from a FRESH LINKED
#      WORKTREE of this very checkout — not by reasoning about why it should, by
#      actually running it there and reading the summary line.
#   2. install.sh ITSELF still refuses to run from that same worktree — the guard this
#      task was told not to weaken. A fix that made the guard permissive instead of
#      teaching the test to route around it would flip this half red.
#
# HOW. `git worktree add` only ever checks out committed content, so this necessarily
# tests HEAD, not uncommitted edits — the same limitation every git-worktree fixture in
# this suite accepts (see installer-worktree-guard.test.sh's make_template, which commits
# before adding a worktree). That is the right tradeoff here too: CI always runs from a
# commit, never from someone's dirty tree.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

# The repo root is handed to `cd` as an ALREADY-RESOLVED variable, never as a nested
# substitution: this path is named in the EXIT trap below, and tests/harness-temp-safety.sh
# refuses `cd "$(...)"` for any trap-referenced path (its NESTED-CD class). Splitting the
# assignment is the shape that file asks for -- "the canonicalising cd must be handed a
# variable already known good" -- not a way around it.
REPO_REL="$(dirname "$0")/.."
[ -d "$REPO_REL" ] || { echo "worktree-suite-parity.test: cannot locate repo root from $0" >&2; exit 2; }
REPO="$(cd -- "$REPO_REL" && pwd)"
[ -n "$REPO" ] && [ -d "$REPO" ] || { echo "worktree-suite-parity.test: repo root did not resolve" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/worktree-suite-parity.XXXXXX")" || {
  echo "worktree-suite-parity.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
WT="$TMP/wt"
trap 'git -C "$REPO" worktree remove --force "$WT" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

git -C "$REPO" worktree add -q --detach "$WT" HEAD >/dev/null 2>&1 || {
  echo "worktree-suite-parity.test: could not create a worktree from $REPO at HEAD." >&2; exit 2; }

# --- half 1: the guard this task must not weaken is still there -------------
guard_out="$(bash "$WT/install.sh" "$TMP/never-stamped" 2>&1)"; guard_rc=$?
ok "install.sh still refuses to run from this worktree" "$guard_rc" 2
ok "…still says why"                                     "$(printf '%s' "$guard_out" | grep -qi 'refusing to install from a git worktree' && echo yes || echo no)" yes
ok "…still stamped nothing"                              "$(find "$TMP/never-stamped" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" 0

# --- half 2: board-renderers.test.sh no longer depends on install.sh having run
# from a location the guard above would refuse -------------------------------
br_out="$(bash "$WT/tests/board-renderers.test.sh" 2>&1)"; br_rc=$?
br_summary="$(printf '%s\n' "$br_out" | grep -oE 'pass=[0-9]+ fail=[0-9]+' | tail -n1)"
if [ -z "$br_summary" ]; then
  echo "worktree-suite-parity.test: board-renderers.test.sh printed no pass=/fail= summary:" >&2
  printf '%s\n' "$br_out" >&2
  fail=$((fail+1))
else
  br_pass="$(printf '%s' "$br_summary" | sed -E 's/pass=([0-9]+).*/\1/')"
  br_fail="$(printf '%s' "$br_summary" | sed -E 's/.*fail=([0-9]+)/\1/')"
  ok "board-renderers.test.sh exits 0 from a linked worktree"    "$br_rc" 0
  ok "…and reports fail=0"                                       "$br_fail" 0
  # A vacuous pass (0 assertions run) would satisfy "fail=0" too — reject it explicitly,
  # the same shape task-024 found in this exact file.
  ok "…having actually run some assertions, not zero"            "$([ "$br_pass" -gt 0 ] && echo yes || echo no)" yes
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
