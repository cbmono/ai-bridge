#!/usr/bin/env bash
#
# reclaim-worktree.test.sh — exercises plugin/scripts/reclaim-worktree.sh, the ONE
# script in this template that deletes a worktree.
#
# WHY THIS HARNESS EXISTS AT ALL. The pruner's delete path destroyed three running
# agents' worktrees (2026-08-04) and was removed for good. Reclaim is allowed back
# only because it deletes ONE path that a task RECORDED, instead of a path it
# inferred from a scan — so what has to be proven here is not that removal works
# (one assertion) but that every refusal holds (most of this file). A guard that
# quietly stops firing turns this script back into the one that caused the
# incident, and the only thing standing between those two is the matrix below.
#
# Properties it guarantees, and which any change to the script must preserve:
#   1. It never touches the real reposRoot or a real worktree. It builds its own
#      instance dir whose instance.config.json points at an mktemp tree, and
#      asserts every path the script names is inside that tree.
#   2. It builds OUTSIDE any synced folder, and refuses to run if $TMPDIR is
#      inside one — a Dropbox-backed fixture can have its files rewritten mid-run.
#   3. ONE fixture is removed in the whole run: the clean, pushed, branch-attached,
#      PR-merged worktree recorded on a `done` task. Every other fixture is still
#      registered and still on disk when the run ends, asserted as a blanket
#      property over the matrix rather than only per case.
#   4. Both directions, per the test conventions: each guard is shown to REFUSE on
#      the fixture that trips it, and the liveness veto is additionally shown to be
#      the thing that refused (the same worktree clears with the veto disabled).
#      A harness that only asserts refusals would pass a script that refuses
#      everything, which is also a broken script — it would silently never reclaim.
#
# `gh` is stubbed (a fake `gh` first on PATH) so PR state is a fixture, not a
# network call. It answers only `gh pr view <url> --json state --jq .state` and
# exits non-zero on anything else, so a new gh call surfaces as a failure here
# instead of silently degrading to "unknown" (which the script refuses on anyway).
#
# assert(): 0 is a PASS, matching the other harnesses here.
#
# Usage:  tests/reclaim-worktree.test.sh
#         RECLAIM=/path/to/reclaim-worktree.sh tests/reclaim-worktree.test.sh
set -uo pipefail

RECLAIM="${RECLAIM:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/reclaim-worktree.sh}"
TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"

die() { printf 'reclaim-worktree.test: %s\n' "$*" >&2; exit 2; }
[ -f "$RECLAIM" ] || die "script not found at $RECLAIM"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reclaim-fixture.XXXXXX")" || die "mktemp failed"
# Canonicalize: on macOS $TMPDIR is a symlink (/var -> /private/var) and
# `git worktree list --porcelain` prints resolved paths. Comparing an unresolved
# path against a resolved one matches nothing — the trap that has appeared three
# times in this codebase, and which the script itself canonicalizes for.
TMP="$(cd "$TMP" && pwd -P)"
case "$TMP" in
  *Dropbox*|*iCloud*|*"Google Drive"*|*OneDrive*)
    rm -rf "$TMP"; die "refusing to build fixtures inside a synced folder ($TMP)" ;;
esac
trap 'rm -rf "$TMP"' EXIT

ORIGIN="$TMP/origin.git"
REPOS="$TMP/repos"
REPO="$REPOS/proj"
WTROOT="$TMP/wt"
OUTSIDE="$TMP/outside"
INSTANCE="$TMP/instance"
FIXTURES="$TMP/gh-fixtures"
TASKS="$INSTANCE/projects/demo/tasks"

mkdir -p "$REPOS" "$WTROOT" "$OUTSIDE" "$TASKS" "$TMP/bin" "$TMP/nogh"

cat > "$INSTANCE/instance.config.json" <<JSON
{
  "org": "fixture-org",
  "reposRoot": "$REPOS",
  "worktreeRoot": "$WTROOT",
  "authorEmail": "fixture@example.com"
}
JSON
# The script requires an instance root (SCHEMA.md + instance.config.json), exactly
# as task-owner.sh does. A copy of the real one, so the fixture cannot drift from
# what an instance actually has.
cp "$TPLSRC/seed/SCHEMA.md" "$INSTANCE/SCHEMA.md"

# --- the upstream + clone -----------------------------------------------------
g() { git -C "$REPO" "$@"; }

git init -q -b main "$REPO"
g config user.email fixture@example.com
g config user.name  Fixture
g config commit.gpgsign false
printf 'one\n' > "$REPO/tracked.txt"
printf 'ignored-local/\n' > "$REPO/.gitignore"
g add tracked.txt .gitignore; g commit -qm 'c1'
git init -q --bare -b main "$ORIGIN"
g remote add origin "$ORIGIN"
g push -q -u origin main
g remote set-head origin -a >/dev/null

# A worktree on a branch, with one commit, pushed. The shape a finished dispatch
# has: nothing uncommitted, nothing unpushed.
wt_pushed() { # <path> <branch>
  git -C "$REPO" worktree add -q "$1" -b "$2" origin/main >/dev/null
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name Fixture
  printf 'work\n' > "$1/feature.txt"
  git -C "$1" add feature.txt
  git -C "$1" commit -qm "work on $2"
  git -C "$1" push -q -u origin "$2"
}

# A worktree detached at a sha that is on NO ref — what a squash-merged PR head
# looks like once its remote branch is deleted, and the class whose commits a
# removal destroys irrecoverably.
wt_detached() { # <path> -> prints the sha
  local tmpbr="tmp/$(basename "$1")"
  g branch -q "$tmpbr" main
  git -C "$REPO" worktree add -q --detach "$1" "$tmpbr" >/dev/null
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name Fixture
  printf 'detached work\n' > "$1/feature.txt"
  git -C "$1" add feature.txt
  git -C "$1" commit -qm 'detached work'
  g branch -qD "$tmpbr"
  git -C "$1" rev-parse HEAD
}

# --- task documents -----------------------------------------------------------
# `-` omits a key entirely, which is how "absent" is tested: an empty value would
# be a different case (the script reads it as absent too, but a scaffold carrying
# a bare key is the realistic shape).
PR1="https://github.com/fixture-org/proj/pull/1"
PR2="https://github.com/fixture-org/proj/pull/2"
PR_OTHER="https://github.com/fixture-org/other/pull/9"

write_task() { # <id> <status> <worktree|-> <branch|-> <target_repo|-> <pr-urls...|->
  local id=$1 st=$2 wt=$3 br=$4 tr=$5; shift 5
  {
    echo "---"
    echo "type: Task"
    echo "title: fixture $id"
    echo "description: fixture task"
    echo "kind: build"
    echo "status: $st"
    [ "$tr" = "-" ] || echo "target_repo: $tr"
    [ "$wt" = "-" ] || echo "worktree: $wt"
    [ "$br" = "-" ] || echo "branch: $br"
    if [ "${1:-}" = "-" ] || [ "$#" -eq 0 ]; then
      echo "pr: [ ]"
    else
      printf 'pr: [ %s ]\n' "$(printf '%s, ' "$@" | sed 's/, $//')"
    fi
    echo "timestamp: 2026-08-23T00:00:00Z"
    echo "---"
    echo
    echo "# Context"
    echo "A fixture task."
  } > "$TASKS/$id.md"
}

# --- gh stub ------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" != pr ] || [ "${2:-}" != view ]; then
  echo "gh-stub: unhandled invocation: $*" >&2; exit 1
fi
url="${3:-}"
state="$(awk -v u="$url" '$1 == u { print $2 }' "${GH_FIXTURES:?}")"
[ -n "$state" ] || { echo "gh-stub: no fixture for $url" >&2; exit 1; }
printf '%s\n' "$state"
STUB
chmod +x "$TMP/bin/gh"

cat > "$FIXTURES" <<EOF
$PR1 MERGED
$PR2 OPEN
$PR_OTHER MERGED
EOF

# --- runner -------------------------------------------------------------------
# PRUNE_ACTIVE_MINUTES=0 for the guard matrix: every fixture was created seconds
# ago, so the liveness veto would otherwise refuse them all and no other guard
# would ever be reached. Two scenarios below assert the veto itself, with the
# default window.
OUT=""; RC=0
run() { # <args...>   → sets OUT and RC
  OUT="$( cd "$INSTANCE" \
    && PATH="${STUB_PATH:-$TMP/bin:$PATH}" \
       GH_FIXTURES="$FIXTURES" \
       PRUNE_ACTIVE_MINUTES="${ACTIVE_MINUTES:-0}" \
       bash "$RECLAIM" "$@" 2>&1 )"
  RC=$?
}

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
eq()     { [ "$1" = "$2" ] && echo 0 || echo 1; }
has()    { printf '%s\n' "$OUT" | grep -Eq -- "$1" && echo 0 || echo 1; }

registered() { # <path> — is it still a registered worktree of the fixture repo?
  git -C "$REPO" worktree list --porcelain | grep -Fxq "worktree $1"
}

# The refusal shape, asserted the same way every time: exit 1, a message naming
# the reason, and the worktree STILL THERE — on disk and registered. The third
# assertion is the one that matters: a refusal that printed the right words while
# removing the directory anyway would pass the first two.
refusal() { # <label> <task-id> <reason-regex> <worktree-path|->
  local label=$1 id=$2 want=$3 wt=$4
  run "projects/demo/tasks/$id.md"
  assert "$label: exits 1"            "$(eq "$RC" 1)"
  assert "$label: says why"           "$(has "$want")"
  if [ "$wt" != "-" ]; then
    assert "$label: worktree survives"   "$(yes_if test -d "$wt")"
    assert "$label: still registered"    "$(yes_if registered "$wt")"
  fi
}

echo "== guard matrix: every refusal, with the liveness veto disabled =="

# --- G2: only a `done` task may reclaim --------------------------------------
# `cancelled` is deliberately NOT enough: its PR was closed unmerged, so that
# worktree can hold the only copy of the work. Same worktree, three statuses.
WT_STATUS="$WTROOT/proj-demo-status"
wt_pushed "$WT_STATUS" okf/demo-status
write_task task-status-cancelled cancelled  "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-review    in-review  "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-progress  in-progress "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
refusal "G2 cancelled"   task-status-cancelled 'refuse:.*not .done.'   "$WT_STATUS"
refusal "G2 in-review"   task-status-review    'refuse:.*not .done.'   "$WT_STATUS"
refusal "G2 in-progress" task-status-progress  'refuse:.*not .done.'   "$WT_STATUS"

# --- G3: what the task records ----------------------------------------------
# No worktree recorded ⇒ do NOTHING (exit 3). The script must never go looking
# for a candidate; that search is the scan whose inference caused the incident.
write_task task-no-worktree done - - fixture-org/proj "$PR1"
run "projects/demo/tasks/task-no-worktree.md"
assert "G3 no worktree recorded: exits 3 (nothing to do)" "$(eq "$RC" 3)"
assert "G3 no worktree recorded: says so"                 "$(has 'noop:.*records no .worktree')"

# A `worktree:` line in the BODY is not a record. The frontmatter reader is
# scoped for exactly this: an unterminated or unscoped read would turn prose into
# a delete instruction.
cat > "$TASKS/task-body-only.md" <<EOF
---
type: Task
title: fixture body-only
status: done
target_repo: fixture-org/proj
pr: [ $PR1 ]
timestamp: 2026-08-23T00:00:00Z
---

# Notes
worktree: $WT_STATUS
branch: okf/demo-status
EOF
run "projects/demo/tasks/task-body-only.md"
assert "G1 a worktree: line in the BODY is not a record" "$(eq "$RC" 3)"
assert "G1 …and that worktree survives"                  "$(yes_if test -d "$WT_STATUS")"

# A recorded worktree with NO recorded branch is a refusal, not a licence to skip
# the branch check. A missing guard input must never read as a passed guard.
write_task task-no-branch done "$WT_STATUS" - fixture-org/proj "$PR1"
refusal "G3 no branch recorded" task-no-branch 'refuse:.*no .branch:' "$WT_STATUS"

# --- G4: the path must be one of ours ---------------------------------------
# A REGISTERED, clean, pushed, PR-merged worktree of the right repo — sitting
# outside both worktree roots. Everything else about it passes, so this fixture
# isolates the root check.
WT_OUT="$OUTSIDE/proj-demo-outside"
wt_pushed "$WT_OUT" okf/demo-outside
write_task task-outside done "$WT_OUT" okf/demo-outside fixture-org/proj "$PR1"
refusal "G4 outside the worktree roots" task-outside \
  'refuse:.*not inside this instance.s worktree roots' "$WT_OUT"

write_task task-relative done "wt/relative" okf/x fixture-org/proj "$PR1"
refusal "G4 a relative path" task-relative 'refuse:.*not an absolute path' -

write_task task-dotdot done "$WTROOT/../wt/x" okf/x fixture-org/proj "$PR1"
refusal "G4 a path containing .." task-dotdot "refuse:.*contains" -

write_task task-gone done "$WTROOT/never-existed" okf/x fixture-org/proj "$PR1"
run "projects/demo/tasks/task-gone.md"
assert "G4 a recorded path that is gone: exits 3" "$(eq "$RC" 3)"
assert "G4 …and calls it already reclaimed"       "$(has 'noop:.*already reclaimed')"

# The repo itself must never be removable through this path.
write_task task-is-repo done "$REPO" main fixture-org/proj "$PR1"
refusal "G4 the repo itself" task-is-repo 'refuse:' -
assert "G4 the repo itself: repo survives" "$(yes_if test -e "$REPO/.git")"

# --- G5: the expected repo comes from the task ------------------------------
WT_NOREPO="$WTROOT/proj-demo-norepo"
wt_pushed "$WT_NOREPO" okf/demo-norepo
write_task task-no-target done "$WT_NOREPO" okf/demo-norepo - "$PR1"
refusal "G5 no target_repo recorded" task-no-target 'refuse:.*no .target_repo:' "$WT_NOREPO"

write_task task-uncloned done "$WT_NOREPO" okf/demo-norepo fixture-org/absent "$PR1"
refusal "G5 target_repo not cloned" task-uncloned 'refuse:.*is not cloned' "$WT_NOREPO"

# --- G6: it must be a registered worktree of that repo ----------------------
# A plain directory inside the worktree root: a rescued tree, a hand-made copy or
# a cache dir. Not ours to delete, however finished the task is.
PLAIN="$WTROOT/plain-directory"
mkdir -p "$PLAIN"; printf 'somebody work\n' > "$PLAIN/leftover.txt"
write_task task-unregistered done "$PLAIN" okf/demo-plain fixture-org/proj "$PR1"
run "projects/demo/tasks/task-unregistered.md"
assert "G6 an unregistered directory: exits 1"    "$(eq "$RC" 1)"
assert "G6 an unregistered directory: says why"   "$(has 'refuse:.*not a registered worktree')"
assert "G6 an unregistered directory: survives"   "$(yes_if test -f "$PLAIN/leftover.txt")"

# A registered worktree of ANOTHER repo under reposRoot, recorded against this
# one: the record and git must agree about which repo owns the path.
OTHER="$REPOS/other"
git init -q -b main "$OTHER"
git -C "$OTHER" config user.email fixture@example.com
git -C "$OTHER" config user.name Fixture
printf 'x\n' > "$OTHER/f.txt"; git -C "$OTHER" add f.txt; git -C "$OTHER" commit -qm c1
WT_WRONGREPO="$WTROOT/other-demo-wrongrepo"
git -C "$OTHER" worktree add -q "$WT_WRONGREPO" -b okf/demo-wrongrepo main >/dev/null
write_task task-wrong-repo done "$WT_WRONGREPO" okf/demo-wrongrepo fixture-org/proj "$PR1"
run "projects/demo/tasks/task-wrong-repo.md"
assert "G6 a worktree of another repo: exits 1"  "$(eq "$RC" 1)"
assert "G6 a worktree of another repo: says why" "$(has 'refuse:.*not a registered worktree')"
assert "G6 a worktree of another repo: survives" "$(yes_if test -d "$WT_WRONGREPO")"

# --- G7: a lock is an explicit "do not touch" -------------------------------
WT_LOCKED="$WTROOT/proj-demo-locked"
wt_pushed "$WT_LOCKED" okf/demo-locked
git -C "$REPO" worktree lock "$WT_LOCKED"
write_task task-locked done "$WT_LOCKED" okf/demo-locked fixture-org/proj "$PR1"
refusal "G7 locked" task-locked 'refuse:.*LOCKED' "$WT_LOCKED"

# --- G8: detached, and branch identity --------------------------------------
# Detached at a merged PR head: every other guard passes, and it must STILL be
# refused — removal deletes the only reachability those commits have.
WT_DETACHED="$WTROOT/proj-demo-detached"
S_DETACHED="$(wt_detached "$WT_DETACHED")"
write_task task-detached done "$WT_DETACHED" okf/demo-detached fixture-org/proj "$PR1"
refusal "G8 detached HEAD" task-detached 'refuse:.*DETACHED HEAD' "$WT_DETACHED"
run "projects/demo/tasks/task-detached.md"
assert "G8 detached HEAD: offers the rescue command" "$(has "branch <name> $S_DETACHED")"
assert "G8 detached HEAD: its commit is still there" \
  "$(yes_if git -C "$REPO" cat-file -e "$S_DETACHED^{commit}")"

# A recycled PATH: the directory now holds a different task's branch. Only the
# recorded branch tells that apart from the worktree this task created.
WT_RECYCLED="$WTROOT/proj-demo-recycled"
wt_pushed "$WT_RECYCLED" okf/demo-actual
write_task task-recycled done "$WT_RECYCLED" okf/demo-recorded fixture-org/proj "$PR1"
refusal "G8 branch mismatch (recycled path)" task-recycled \
  'refuse:.*but .*recorded' "$WT_RECYCLED"

# --- G9: nothing uncommitted -------------------------------------------------
WT_DIRTY="$WTROOT/proj-demo-dirty"
wt_pushed "$WT_DIRTY" okf/demo-dirty
printf 'local edit\n' >> "$WT_DIRTY/tracked.txt"
write_task task-dirty done "$WT_DIRTY" okf/demo-dirty fixture-org/proj "$PR1"
refusal "G9 a modified tracked file" task-dirty 'refuse:.*uncommitted changes' "$WT_DIRTY"

# Untracked work that the PRUNER's name heuristic would call "scaffolding". The
# pruner may downgrade such a worktree to a report line; this script DELETES, so
# there is no scaffolding allowance at all. Deleting that distinction is invisible
# without this fixture.
WT_SCAFF="$WTROOT/proj-demo-scaffolding"
wt_pushed "$WT_SCAFF" okf/demo-scaffolding
printf 'probe\n' > "$WT_SCAFF/probe-viewof.ts"
write_task task-scaffolding done "$WT_SCAFF" okf/demo-scaffolding fixture-org/proj "$PR1"
refusal "G9 untracked scaffolding is NOT an allowance" task-scaffolding \
  'refuse:.*uncommitted changes' "$WT_SCAFF"

# --- G10: nothing unpushed ---------------------------------------------------
# The PR is MERGED in the stub, so if this fixture were removed the reason would
# be a passing G11 — which is exactly the false-pass shape to rule out here.
WT_UNPUSHED="$WTROOT/proj-demo-unpushed"
wt_pushed "$WT_UNPUSHED" okf/demo-unpushed
printf 'more\n' >> "$WT_UNPUSHED/feature.txt"
git -C "$WT_UNPUSHED" commit -qam 'a commit that was never pushed'
write_task task-unpushed done "$WT_UNPUSHED" okf/demo-unpushed fixture-org/proj "$PR1"
refusal "G10 an unpushed commit" task-unpushed \
  'refuse:.*commit\(s\) that no remote-tracking ref' "$WT_UNPUSHED"

# --- G11: every recorded PR merged, checked BY URL --------------------------
WT_PR="$WTROOT/proj-demo-pr"
wt_pushed "$WT_PR" okf/demo-pr
write_task task-pr-open done "$WT_PR" okf/demo-pr fixture-org/proj "$PR2"
refusal "G11 an open PR" task-pr-open 'refuse:.*is OPEN, not MERGED' "$WT_PR"

# A fan-out task: one merged, one open. A task stays unfinished until ALL merge.
write_task task-pr-mixed done "$WT_PR" okf/demo-pr fixture-org/proj "$PR1" "$PR2"
refusal "G11 one of two PRs still open" task-pr-mixed 'refuse:.*is OPEN, not MERGED' "$WT_PR"

write_task task-pr-none done "$WT_PR" okf/demo-pr fixture-org/proj -
refusal "G11 no PR recorded at all" task-pr-none 'refuse:.*records no PR URL' "$WT_PR"

# A merged PR in a DIFFERENT repo is not evidence about this repo's worktree.
write_task task-pr-other done "$WT_PR" okf/demo-pr fixture-org/proj "$PR_OTHER"
refusal "G11 the only merged PR is in another repo" task-pr-other \
  'refuse:.*belongs to' "$WT_PR"

# An unknown PR state (the stub exits non-zero: auth, network, a deleted PR) must
# refuse. An unknown is never what authorises a deletion.
write_task task-pr-unknown done "$WT_PR" okf/demo-pr fixture-org/proj \
  "https://github.com/fixture-org/proj/pull/404"
refusal "G11 gh cannot read the PR" task-pr-unknown 'refuse:.*could not read' "$WT_PR"

# No gh at all. PATH without the stub (and without a real gh) — the shape of an
# offline machine or a container that never installed it.
write_task task-pr-nogh done "$WT_PR" okf/demo-pr fixture-org/proj "$PR1"
STUB_PATH="$TMP/nogh:/usr/bin:/bin" run "projects/demo/tasks/task-pr-nogh.md"
assert "G11 no gh available: exits 1"  "$(eq "$RC" 1)"
assert "G11 no gh available: says why" "$(has 'refuse: gh is not available')"
assert "G11 no gh available: survives" "$(yes_if test -d "$WT_PR")"

# --- usage / environment -----------------------------------------------------
run
assert "no task path: exits 2"        "$(eq "$RC" 2)"
run --bogus "projects/demo/tasks/task-no-worktree.md"
assert "an unknown option: exits 2"   "$(eq "$RC" 2)"
run "projects/demo/tasks/absent.md"
assert "a missing task doc: exits 2"  "$(eq "$RC" 2)"
OUTSIDE_RC=0
OUT="$( cd "$TMP" && bash "$RECLAIM" "instance/projects/demo/tasks/task-no-worktree.md" 2>&1 )" \
  || OUTSIDE_RC=$?
assert "run outside an instance root: exits 2" "$(eq "$OUTSIDE_RC" 2)"
assert "…and says what it wanted"              \
  "$(printf '%s\n' "$OUT" | grep -q 'instance root' && echo 0 || echo 1)"

# --- the blanket property: the matrix removed NOTHING ------------------------
# Per-case assertions only prove the cases they name. This says the whole refusal
# matrix left the disk as it found it — which is what makes a guard's removal loud
# even in a fixture nobody thought to assert.
echo "== blanket: the refusal matrix removed nothing =="
MATRIX_WT="$(git -C "$REPO" worktree list --porcelain | grep '^worktree ' | sort)"
MATRIX_DIRS="$(ls -1 "$WTROOT" "$OUTSIDE" 2>/dev/null | sort)"
assert "every fixture worktree is still registered" \
  "$([ "$(printf '%s\n' "$MATRIX_WT" | wc -l | tr -d ' ')" -ge 9 ] && echo 0 || echo 1)"
assert "no fixture directory was deleted by any refusal" \
  "$(yes_if test -d "$WT_STATUS" -a -d "$WT_LOCKED" -a -d "$WT_DETACHED" -a -d "$WT_DIRTY" \
       -a -d "$WT_UNPUSHED" -a -d "$WT_PR" -a -d "$WT_SCAFF" -a -d "$WT_RECYCLED" -a -d "$WT_OUT")"

# Isolation: nothing the script printed points outside the fixture tree.
assert "no output mentions a synced path" \
  "$(printf '%s\n' "$OUT" | grep -Eq 'Dropbox|iCloud|OneDrive' && echo 1 || echo 0)"

# --- the positive case: dry run, then the removal ----------------------------
# Clean, pushed, branch-attached, PR merged, recorded on a `done` task. If this
# does NOT get removed, the script refuses everything — a harness of refusals
# alone would call that a pass, which is the other broken script.
echo "== the positive case: a finished worktree is reclaimed =="
WT_GOOD="$WTROOT/proj-demo-good"
wt_pushed "$WT_GOOD" okf/demo-good
write_task task-good done "$WT_GOOD" okf/demo-good fixture-org/proj "$PR1"

run --dry-run "projects/demo/tasks/task-good.md"
assert "dry run: exits 0 (every guard passed)" "$(eq "$RC" 0)"
assert "dry run: says it WOULD remove"         "$(has 'would remove: ')"
assert "dry run: removed nothing"              "$(yes_if test -d "$WT_GOOD")"
assert "dry run: still registered"             "$(yes_if registered "$WT_GOOD")"

run "projects/demo/tasks/task-good.md"
assert "removal: exits 0"                      "$(eq "$RC" 0)"
assert "removal: reports the path and branch"  "$(has "removed: $WT_GOOD  \[okf/demo-good\]")"
assert "removal: the directory is gone"        "$(no_if test -d "$WT_GOOD")"
assert "removal: it is deregistered"           "$(no_if registered "$WT_GOOD")"
# The branch ref surviving is why a mis-identification costs a checkout and never
# work: removal deletes the working directory and the admin entry, not history.
assert "removal: the branch ref survives" \
  "$(yes_if git -C "$REPO" show-ref --verify --quiet refs/heads/okf/demo-good)"
assert "removal: the commit survives" \
  "$(yes_if git -C "$REPO" cat-file -e "okf/demo-good^{commit}")"
assert "removal: no other worktree went with it" "$(yes_if test -d "$WT_STATUS")"

# Idempotent: the same call again is silence, not an error and not a second
# removal attempt. This is the re-run a PM tick makes.
run "projects/demo/tasks/task-good.md"
assert "a repeat run: exits 3 (nothing to do)"  "$(eq "$RC" 3)"
assert "a repeat run: says already reclaimed"   "$(has 'noop:.*already reclaimed')"

# --- G12: the liveness veto, and BOTH directions ----------------------------
# The one guard that clears with time, so it is the one that must be shown to be
# the thing refusing — otherwise "it refused" proves nothing about the veto.
echo "== G12: the liveness veto (default window), both directions =="
WT_LIVE="$WTROOT/proj-demo-live"
wt_pushed "$WT_LIVE" okf/demo-live
write_task task-live done "$WT_LIVE" okf/demo-live fixture-org/proj "$PR1"
ACTIVE_MINUTES=120 run --dry-run "projects/demo/tasks/task-live.md"
assert "G12 a seconds-old worktree: exits 1"  "$(eq "$RC" 1)"
assert "G12 …says it was touched recently"    "$(has 'refuse:.*touched within')"
ACTIVE_MINUTES=0 run --dry-run "projects/demo/tasks/task-live.md"
assert "G12 the veto is what refused (0 clears the same fixture)" "$(eq "$RC" 0)"

# RECURSIVE. An agent editing `src/**` never touches the worktree ROOT's mtime, so
# a root-only check calls this idle and removes a worktree being worked in right
# now. Age the root and every top-level entry, leave one file two levels down.
echo "== G12: liveness reaches below the worktree root =="
WT_NESTED="$WTROOT/proj-demo-nested"
wt_pushed "$WT_NESTED" okf/demo-nested
mkdir -p "$WT_NESTED/src/deep"
printf 'live\n' > "$WT_NESTED/src/deep/live.ts"
git -C "$WT_NESTED" add src/deep/live.ts
git -C "$WT_NESTED" commit -qm 'a file below the root'
git -C "$WT_NESTED" push -q origin okf/demo-nested
write_task task-nested done "$WT_NESTED" okf/demo-nested fixture-org/proj "$PR1"
for e in "$WT_NESTED"/* "$WT_NESTED"/.[!.]*; do
  [ -e "$e" ] && touch -t 200001010000 "$e"
done
touch -t 200001010000 "$WT_NESTED"
assert "the aged worktree's own root looks idle (fixture is meaningful)" \
  "$([ -z "$(find "$WT_NESTED" -maxdepth 1 -mmin -120 2>/dev/null | head -1)" ] && echo 0 || echo 1)"
ACTIVE_MINUTES=120 run --dry-run "projects/demo/tasks/task-nested.md"
assert "G12 activity below the root still vetoes"  "$(eq "$RC" 1)"
assert "G12 …and names the liveness reason"        "$(has 'refuse:.*touched within')"

# --- worktreeRoot absent: the legacy <reposRoot>/_wt fallback ----------------
# Instances stamped before the key exists put worktrees in the legacy root, and
# every doc naming `worktreeRoot` has to state that fallback — so the script must
# honour it rather than refusing every older instance's path.
echo "== worktreeRoot absent: the legacy <reposRoot>/_wt root is accepted =="
mkdir -p "$REPOS/_wt"
WT_LEGACY="$REPOS/_wt/proj-demo-legacy"
wt_pushed "$WT_LEGACY" okf/demo-legacy
write_task task-legacy done "$WT_LEGACY" okf/demo-legacy fixture-org/proj "$PR1"
cat > "$INSTANCE/instance.config.json" <<JSON
{ "reposRoot": "$REPOS", "authorEmail": "fixture@example.com" }
JSON
run --dry-run "projects/demo/tasks/task-legacy.md"
assert "a legacy-root worktree is accepted with no worktreeRoot key" "$(eq "$RC" 0)"
# …and the configured root's paths are NOT accepted when the key is absent.
write_task task-live-legacycfg done "$WT_LIVE" okf/demo-live fixture-org/proj "$PR1"
run --dry-run "projects/demo/tasks/task-live-legacycfg.md"
assert "with no worktreeRoot, a path under the unconfigured root is refused" "$(eq "$RC" 1)"


echo "--- G1b: a task document from OUTSIDE this instance is refused -------------"
# The hole the review found: the prefix strip left `rel` absolute for a path outside the
# instance, so every later guard then read an attacker-chosen file. A `done` task carrying
# a matching worktree:, branch:, target_repo: and a merged PR URL would pass all of them
# and remove a clean, registered worktree this instance never dispatched. The authority for
# deleting a worktree is THIS bundle's own record of having created it — a well-formed
# document from anywhere else is not evidence.
EXT="$TMP/outside"; mkdir -p "$EXT"
# Copy a task that WOULD otherwise pass every guard, so the refusal can only come from
# the location check. That is what makes this assertion non-vacuous.
GOODTASK="$(cd "$INSTANCE" && ls projects/*/tasks/*.md 2>/dev/null | head -1)"
if [ -n "$GOODTASK" ]; then
  cp "$INSTANCE/$GOODTASK" "$EXT/stolen.md"
  run "$EXT/stolen.md"
  assert "G1b external task path: refuses (exit 2, a caller error)" "$(eq "$RC" 2)"
  assert "G1b external task path: says why"         "$(has 'not a task document of this instance')"
  assert "G1b external task path: names projects/"  "$(has 'projects/')"
  # And the partner direction: the SAME document, in place, is still accepted far enough
  # to reach a later guard — so the refusal is about location, not about the document.
  run "$GOODTASK"
  assert "G1b the in-place task is NOT refused for location" \
    "$(printf '%s' "$OUT" | grep -q 'not a task document of this instance' && echo 1 || echo 0)"
else
  printf '  SKIP  no fixture task available for the external-path case\n'
fi

# --- verdict ----------------------------------------------------------------
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
