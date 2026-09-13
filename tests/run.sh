#!/usr/bin/env bash
#
# run.sh — the ONE implementation of this repo's harness selection. CI calls it too.
#   --changed [--base <ref>]  the core harnesses plus every harness naming a changed path
#   --all                     every tests/*.test.sh (the default)
#   --ci                      the workflow entry: the fast path on a plugin-only PR diff,
#                             the full suite on anything else
# Every harness is run, the checkout re-verified after it, and its own pass=/fail= line
# parsed — an exit code is never trusted on its own.
# Exit: 0 all green · 1 a harness failed · 2 refused (no harnesses, or a dead checkout).
# Why, the core list and the measured numbers: .claude/rules/tests.md.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "run.sh: cannot locate self" >&2; exit 2; }
workspace="$(cd "$HERE/.." && pwd)" || { echo "run.sh: cannot locate repo root" >&2; exit 2; }
cd "$workspace" || exit 2

# Harnesses no changed path can be expected to name, because they read plugin/ wholesale
# or reach their subject indirectly. .claude/rules/tests.md, "The core", says why each.
CORE=(
  tests/plugin-manifest.test.sh
  tests/plugin-skills.test.sh
  tests/plugin-agents.test.sh
  tests/plugin-eval.test.sh
  tests/deny-baseline.test.sh
  tests/agent-control.test.sh
  tests/commit-as-guard.test.sh
  tests/companion-plugins.test.sh
  tests/harness-read-paths.test.sh
)

usage() { sed -n '3,10p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; }

mode=all
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     mode=all ;;
    --changed) mode=changed ;;
    --ci)      mode=ci ;;
    --base)    shift; base="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

group()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$1"; else echo "== $1"; fi; }
endgroup() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; return 0; }
fatal()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::$1"; else echo "run.sh: $1" >&2; fi; }

# A harness with a broken TMPDIR guard can rm -rf its OWN checkout while still printing a
# clean pass=N fail=0 and exiting 0 — knowledge/findings/suite-cleanup-can-delete-its-own-
# checkout.md in the control panel. `-e` on .git, not `-d`: it is a FILE in a worktree.
verify_checkout() {
  git -C "$workspace" rev-parse --verify -q HEAD >/dev/null 2>&1 \
    && [ -e "$workspace/.git" ] \
    && [ -d "$workspace/tests" ] \
    && [ -d "$workspace/plugin" ]
}

default_base() {
  git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main
}

# select_derived <newline-separated paths> — sets SELECTED and UNNAMED. Not a function
# that prints, because a $( ) subshell would lose UNNAMED, which is half the answer.
# A harness is selected because it NAMES a changed path, or a >=2-component suffix of one
# (so "$REPO/scripts/foo.sh" style references still match; never a bare basename, which
# would match half the suite) — never because somebody remembered to add a line.
select_derived() {
  local changed="$1" p suffix m hits derived=""
  UNNAMED=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    hits=""; suffix="$p"
    while : ; do
      m="$(grep -lF -e "$suffix" tests/*.test.sh 2>/dev/null || true)"
      [ -z "$m" ] || hits="${hits}${m}"$'\n'
      case "$suffix" in
        */*/*) suffix="${suffix#*/}" ;;
        *)     break ;;
      esac
    done
    if [ -z "$hits" ]; then
      UNNAMED="${UNNAMED:+$UNNAMED }$p"
    else
      derived="${derived}${hits}"
    fi
  done <<<"$changed"
  SELECTED="$(printf '%s\n' "${CORE[@]}" "$derived" | grep -v '^[[:space:]]*$' | sort -u)"
}

files_from_selection() {
  files=()
  while IFS= read -r h; do
    [ -n "$h" ] && files+=("$h")
  done <<<"$SELECTED"
}

announce() { # <lead> <changed paths>
  echo "$1"
  [ -z "$2" ] || printf '%s\n' "$2" | sed 's/^/  changed: /'
  [ "${#files[@]}" -eq 0 ] || printf '%s\n' "${files[@]}" | sed 's/^/  harness: /'
}

shopt -s nullglob
files=(tests/*.test.sh)
shopt -u nullglob

# `.git` is a FILE in a linked worktree. init-bundle.sh --config refuses to run from one
# by design, so four harnesses fail there for reasons unrelated to the code under test.
[ -f "$workspace/.git" ] && echo "run.sh: this is a git WORKTREE — derived-indexes, link-repos, snapshot and board-renderers fail here by design (.claude/rules/tests.md). Verify from the main checkout or a fresh clone." >&2

case "$mode" in
  all) ;;

  changed)
    [ -n "$base" ] || base="$(default_base)"
    # Committed, uncommitted and untracked alike: locally the change you want covered is
    # usually not committed yet, which is the whole difference from the CI diff below.
    changed="$( { git diff --name-only "$base...HEAD" 2>/dev/null
                  git diff --name-only HEAD 2>/dev/null
                  git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
    if [ -z "$changed" ]; then
      SELECTED="$(printf '%s\n' "${CORE[@]}" | sort -u)"; UNNAMED=""
      files_from_selection
      announce "no changed paths against $base — running the ${#CORE[@]} core harnesses:" ""
    else
      select_derived "$changed"
      files_from_selection
      announce "changed-path selection — the ${#CORE[@]} core harnesses plus every harness that names a changed path:" "$changed"
      [ -z "$UNNAMED" ] || echo "no harness names these changed paths, so they selected nothing beyond the core — verify with --all before the PR: $UNNAMED"
    fi
    ;;

  ci)
    # PRs only; a push to main always runs everything. The verdict FAILS TOWARD THE FULL
    # SUITE at every step — empty diff, failed fetch, any path outside plugin/ and
    # .claude-plugin/, or a changed path NO harness names. That last one differs from
    # --changed on purpose: this is the merge gate, and there is no --all run after it.
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -n "${GITHUB_BASE_REF:-}" ] \
       && git fetch --quiet origin "$GITHUB_BASE_REF"; then
      changed="$(git diff --name-only "origin/$GITHUB_BASE_REF...HEAD")"
      if [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -qvE '^(plugin/|\.claude-plugin/)'; then
        select_derived "$changed"
        if [ -n "$UNNAMED" ]; then
          echo "plugin-only diff, but no harness names these paths — running the FULL suite: $UNNAMED"
        else
          files_from_selection
          announce "plugin-only diff — running the core plugin harnesses plus every harness that names a changed path:" "$changed"
        fi
      fi
    fi
    ;;
esac

if [ "${#files[@]}" -eq 0 ]; then
  fatal "no tests/*.test.sh files found — refusing to report a vacuous pass"
  exit 2
fi

verify_checkout || { fatal "checkout is not intact before the suite even started"; exit 2; }

total_pass=0
total_fail=0
bad=()
start_ts=$(date +%s)

for f in "${files[@]}"; do
  group "$f"
  f_start=$(date +%s)
  if out="$(bash "$f" 2>&1)"; then rc=0; else rc=$?; fi
  printf '%s\n' "$out"
  echo "-- $f took $(( $(date +%s) - f_start ))s"
  endgroup

  if ! verify_checkout; then
    fatal "the checkout was destroyed while running $f — stopping immediately. See knowledge/findings/suite-cleanup-can-delete-its-own-checkout.md in the control panel."
    exit 2
  fi

  # Two conventions are in use across tests/*.test.sh (.claude/rules/tests.md names both);
  # both are tried, and only their absence counts as "no summary".
  summary="$(printf '%s\n' "$out" | grep -oE 'pass=[0-9]+ fail=[0-9]+' | tail -n1 || true)"
  style=dense
  if [ -z "$summary" ]; then
    summary="$(printf '%s\n' "$out" | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -n1 || true)"
    style=prose
  fi
  if [ -z "$summary" ]; then
    fatal "$f exited $rc but printed no recognised pass/fail summary — the exit code alone is never trusted here"
    bad+=("$f (no summary, exit $rc)")
    continue
  fi

  if [ "$style" = dense ]; then
    f_pass="$(printf '%s' "$summary" | sed -E 's/pass=([0-9]+).*/\1/')"
    f_fail="$(printf '%s' "$summary" | sed -E 's/.*fail=([0-9]+)/\1/')"
  else
    f_pass="$(printf '%s' "$summary" | sed -E 's/^([0-9]+) passed.*/\1/')"
    f_fail="$(printf '%s' "$summary" | sed -E 's/.*, ([0-9]+) failed$/\1/')"
  fi
  total_pass=$((total_pass + f_pass))
  total_fail=$((total_fail + f_fail))

  if [ "$rc" -ne 0 ] || [ "$f_fail" -ne 0 ]; then
    fatal "$f — exit=$rc reported fail=$f_fail"
    bad+=("$f (exit $rc, fail=$f_fail)")
  fi
done

end_ts=$(date +%s)
echo "== ${#files[@]} harness(es) in $((end_ts - start_ts))s — pass=$total_pass fail=$total_fail =="

if [ "${#bad[@]}" -gt 0 ]; then
  echo "FAILED harnesses:"
  printf '  - %s\n' "${bad[@]}"
  exit 1
fi

echo "ok: all ${#files[@]} harnesses passed — exit code AND reported fail=0 both verified for each"
