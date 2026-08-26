#!/usr/bin/env bash
#
# scripts-executable.test.sh — every symlink/scripts/*.sh AND every symlink/.claude/hooks/*.sh
# must be committed executable, because both are invoked as bare paths and nothing else
# grants +x: install.sh symlinks scripts/ straight into an instance, and settings.json
# invokes each hook as "$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh with no installer
# chmod in between — so a committed-644 hook is MORE exposed than a script, not less.
#
# WHY THE INDEX, NOT THE WORKING TREE. `close-project-folder.sh` shipped in ai-bridge#30
# at mode 100644 — the only 644 among what are now 15 scripts here — and the defect was
# invisible on every developer machine because `install.sh` runs `chmod +x` on every
# script it stamps. After that stamp, `test -x` on the working-tree copy is TRUE and
# `git status` shows the file as locally modified (a mode change), while `origin/main`
# still carries 644 and a fresh clone still cannot run it. A check that asks the working
# tree "is this executable" therefore passes on every machine that has ever run
# install.sh and never once observes the actual defect. The only place the true mode
# lives is the git INDEX, read here with `git ls-files -s` — the same tool a fresh clone
# or `git archive` would report, and the only one that is not laundered by the installer.
#
# WHY HEAD TOO, NOT THE INDEX ALONE. The index and HEAD are two different things: `git
# update-index --chmod=+x` (the exact fix command used for close-project-folder.sh)
# changes only the index, staging a mode change that is not committed until a `git
# commit` writes it into a tree. An index-only check can therefore go green on a branch
# whose HEAD still carries the broken 100644 — reproduced below by running that same fix
# command and stopping one step short of a commit: the index alone says 100755, this
# test's original form would have PASSED, and the suite would exit 0 while HEAD (and
# therefore `git archive`, and therefore a real deploy) still had the unexecutable file.
# `main` here has no CI at all — no `.github/workflows/`, an unprotected default branch,
# zero check-runs on any head SHA — so the only place this guard ever runs is a local
# clone someone chose to run it in; it must not be gameable by an uncommitted stage. So
# both are asserted: `git ls-files -s` (index) AND `git ls-tree HEAD` (the committed
# tree). A file has to be 100755 in both, or this fails.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# mode_ok(): PASS (echoes "<idx> <head> 0") only when a path is 100755 in BOTH the index
# and the committed HEAD tree of the git repo rooted at the caller's cwd; otherwise the
# third field is 1. Run against the real template below, and — unchanged — against a
# disposable fixture repo further down that reproduces the exact defect this exists to
# catch. The same function has to reject the fixture or this test proves nothing.
mode_ok() {
  local f="$1" idx head
  idx="$(git ls-files -s -- "$f" | awk '{print $1}')"
  head="$(git ls-tree HEAD -- "$f" 2>/dev/null | awk '{print $1}')"
  if [[ "$idx" == 100755 && "$head" == 100755 ]]; then
    printf '%s %s 0\n' "$idx" "$head"
  else
    printf '%s %s 1\n' "$idx" "$head"
  fi
}

cd "$TPL" || { echo "scripts-executable.test: cannot cd to $TPL" >&2; exit 2; }

# check_group <label> <min-count> <glob...> — asserts every matching tracked file is
# 100755 at index AND HEAD, and that at least <min-count> files were actually checked
# (a check over an empty match is a check over nothing).
check_group() {
  local label="$1" min="$2"; shift 2
  local files count=0 f idx head rc
  files="$(git ls-files "$@")"
  assert "there is at least one $label to check" "$([ -n "$files" ] && echo 0 || echo 1)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count+1))
    read -r idx head rc < <(mode_ok "$f")
    assert "$f is committed 100755 at index AND HEAD (index=$idx head=$head)" "$rc"
  done <<EOF
$files
EOF
  assert "…and every $label was actually checked ($min or more)" \
    "$([ "$count" -ge "$min" ] && echo 0 || echo 1)"
}

echo "== symlink/scripts — install.sh chmods these on stamp, but the repo itself must be right =="
# The glob below is QUOTED and handed to `git ls-files` as a pathspec, not expanded by
# this shell against the working tree. An unquoted `symlink/scripts/*.sh` here would be
# expanded by bash BEFORE check_group ever runs, against whatever happens to exist on
# disk right now — so a file that is committed 100755 but has since been deleted only
# from the worktree (still tracked, still in HEAD) would never even reach `git ls-files`
# and would silently drop out of the check. Quoting routes the pattern through git's own
# index-backed glob matching instead — the one source this test's header already says to
# trust. See the "guard D" reproduction below, which pins this exact shape.
check_group "symlink/scripts/*.sh" 15 'symlink/scripts/*.sh'

echo "== symlink/.claude/hooks — bare paths off settings.json, NO installer chmod at all =="
check_group "symlink/.claude/hooks/*.sh" 5 'symlink/.claude/hooks/*.sh'

echo "== guard: a failed 'mktemp -d' must abort, not silently run the fixture at the repo root =="
# Regression test for a real incident shape: if `mktemp -d` fails (e.g. a bogus/unwritable
# TMPDIR) and the result is used unguarded, `FIX=""` and `cd "$FIX"` SUCCEEDS without
# moving (bash treats `cd ""` as a no-op), so every "disposable fixture" command below —
# `git init`, `git commit`, `git config user.name/email` — runs at the repo root of the
# real checkout under test instead of a scratch directory. That mutates the actual repo
# (extra commits landing on whatever branch is checked out, local git identity
# overwritten) and the test still prints a clean `pass=.. fail=0`. Prove the *fixed* guard
# (below) refuses instead, by re-invoking this same script as a child process with a
# TMPDIR that cannot be created under, and checking it exits non-zero without moving the
# real repo's HEAD. `_SCRIPTS_EXEC_TEST_CHILD` stops the child from recursing again.
if [[ "${_SCRIPTS_EXEC_TEST_CHILD:-0}" != 1 ]]; then
  BEFORE_HEAD="$(git rev-parse HEAD)"
  BOGUS_TMPDIR="/nonexistent-scripts-exec-fixture-guard-$$"
  GUARD_OUT="$(cd "$TPL" && TMPDIR="$BOGUS_TMPDIR" _SCRIPTS_EXEC_TEST_CHILD=1 bash "$HERE/scripts-executable.test.sh" 2>&1)"
  GUARD_RC=$?
  AFTER_HEAD="$(git rev-parse HEAD)"
  assert "a failed mktemp -d makes the harness exit non-zero (refuses, doesn't silently pass)" \
    "$([ "$GUARD_RC" -ne 0 ] && echo 0 || echo 1)"
  assert "…and it must not print a clean pass=.. fail=0 summary" \
    "$(printf '%s\n' "$GUARD_OUT" | grep -Eq '^pass=[0-9]+ fail=0$' && echo 1 || echo 0)"
  assert "…and the real repo under test must not gain commits from a fixture that ran at its root" \
    "$([ "$BEFORE_HEAD" == "$AFTER_HEAD" ] && echo 0 || echo 1)"
fi

echo "== the guard itself: does it catch the reproduction, not just today's repo state? =="
# A disposable repo reproducing the exact defect this test exists to catch: committed at
# 100644, then `git update-index --chmod=+x` staged (NOT committed) on top — the exact
# command close-project-folder.sh was fixed with, stopped one step short of a commit. An
# index-only read says PASS here; mode_ok() must say FAIL.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/scripts-exec-fixture.XXXXXX")" || {
  echo "scripts-executable.test: mktemp -d failed; refusing to run the fixture in place" >&2
  exit 1
}
if [[ -z "$FIX" || ! -d "$FIX" ]]; then
  echo "scripts-executable.test: mktemp -d returned an empty/invalid path; refusing to run the fixture in place" >&2
  exit 1
fi
trap 'rm -rf "$FIX"' EXIT
(
  cd "$FIX" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t

  printf '#!/usr/bin/env bash\necho hi\n' > bad.sh
  git add bad.sh >/dev/null
  git commit -qm "committed at 644" >/dev/null   # HEAD tree: 100644
  chmod +x bad.sh
  git update-index --chmod=+x bad.sh             # index only: 100755, HEAD unchanged
)

read -r idx head rc < <(cd "$FIX" && mode_ok bad.sh)
assert "naive index-only read of the reproduction says 100755 (the bug being fixed)" \
  "$([ "$idx" == 100755 ] && echo 0 || echo 1)"
assert "…but HEAD is still 100644, so HEAD=100644/INDEX=100755 now FAILS ($idx/$head)" \
  "$([ "$rc" == 1 ] && echo 0 || echo 1)"

(
  cd "$FIX" || exit 1
  # Undo bad.sh's staged-but-uncommitted chmod before touching good.sh, so the next
  # commit below cannot sweep bad.sh's mode change in along with it — each file's
  # fixture state must stay isolated or this second assertion proves nothing.
  git reset -q HEAD -- bad.sh
  printf '#!/usr/bin/env bash\necho ok\n' > good.sh
  chmod +x good.sh
  git add good.sh >/dev/null
  git update-index --chmod=+x good.sh
  git commit -qm "committed at 755" >/dev/null   # HEAD and index both: 100755
)

read -r idx head rc < <(cd "$FIX" && mode_ok good.sh)
assert "a genuinely committed-755 file still PASSES at index and HEAD" "$rc"

echo "== guard: a file committed 755 then deleted only from the worktree must still be enumerated =="
# Regression test for check_group's file-list source, not just mode_ok()'s file-mode
# read. A 16th script committed at 755 and then `rm`ed from disk only (still tracked at
# 100755 in the index and HEAD) reproduces the exact defect an unquoted call-site glob
# had: bash expands `d-*.sh` against the fixture's working tree BEFORE git ever sees it,
# so the deleted-but-tracked file never reaches `git ls-files` at all — the min-count
# floor does not save it because the other on-disk file(s) still clear it. Quoting the
# pattern (this test's real fix, applied to the two check_group calls above) routes
# enumeration through git's index instead.
(
  cd "$FIX" || exit 1
  printf '#!/usr/bin/env bash\necho good\n' > d-good.sh
  chmod +x d-good.sh
  git add d-good.sh >/dev/null
  git update-index --chmod=+x d-good.sh
  git commit -qm "committed 755, stays on disk" >/dev/null

  printf '#!/usr/bin/env bash\necho gone\n' > d-gone.sh
  chmod +x d-gone.sh
  git add d-gone.sh >/dev/null
  git update-index --chmod=+x d-gone.sh
  git commit -qm "committed 755, then removed from the worktree only" >/dev/null
  rm -f d-gone.sh   # tracked 100755 at index+HEAD; absent from the working tree
)

# Mimics exactly what an unquoted call site does: bash expands the glob into positional
# args itself, before anything downstream ever runs — no `ls`/ subprocess glob involved.
UNQUOTED_COUNT="$(
  cd "$FIX" || exit 1
  shopt -s nullglob
  files=(d-*.sh)
  echo "${#files[@]}"
)"
GIT_COUNT="$(cd "$FIX" && git ls-files -- 'd-*.sh' | wc -l | tr -d ' ')"
assert "an unquoted shell glob only sees the file still present on disk (the old bug shape)" \
  "$([ "$UNQUOTED_COUNT" == 1 ] && echo 0 || echo 1)"
assert "…but 'git ls-files' against the quoted pattern finds both, straight from the index/HEAD" \
  "$([ "$GIT_COUNT" == 2 ] && echo 0 || echo 1)"

pushd "$FIX" >/dev/null || exit 1
check_group "fixture d-*.sh (quoted call site, the fixed shape)" 2 'd-*.sh'
popd >/dev/null || exit 1

echo "== guard: the two real call sites above must stay quoted, not just this isolated fixture =="
# The fixture above proves quoting matters in principle; this proves it's actually applied
# where it counts. Today's real repo has no worktree-deleted-but-tracked script, so an
# unquoted call site wouldn't fail the checks above by itself — this static check is what
# actually catches someone reverting the quoting on the real check_group calls.
SELF="$HERE/scripts-executable.test.sh"
assert "the symlink/scripts/*.sh check_group call is still quoted" \
  "$(grep -qF "check_group \"symlink/scripts/*.sh\" 15 'symlink/scripts/*.sh'" "$SELF" && echo 0 || echo 1)"
assert "the symlink/.claude/hooks/*.sh check_group call is still quoted" \
  "$(grep -qF "check_group \"symlink/.claude/hooks/*.sh\" 5 'symlink/.claude/hooks/*.sh'" "$SELF" && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
