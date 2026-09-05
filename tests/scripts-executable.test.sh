#!/usr/bin/env bash
#
# scripts-executable.test.sh — every plugin/scripts/*.sh, every plugin/hooks/*.sh
# AND every plugin/hooks/*.sh
# must be committed executable, because all are invoked as bare paths and nothing else
# grants +x: install.sh symlinks scripts/ straight into an instance and chmods only those,
# and settings.json invokes each hook as "$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh with
# no installer chmod in between — so a committed-644 hook is MORE exposed than a script,
# not less. (install.sh, upgrade.sh and scripts/add-second-human.sh are bare-path-invoked
# too and get no chmod ever; all three are 100755 today. They are out of scope here only
# because this file is about the two directories install.sh's chmod can LAUNDER, which is
# what made the original defect invisible — not because they are the "only" such files.)
#
# WHY THE INDEX, NOT THE WORKING TREE. `close-project-folder.sh` shipped in ai-bridge#30
# at mode 100644 — the only 644 among what are now 16 scripts here — and the defect was
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
# --- WHY THIS FILE IS SO DEFENSIVE ABOUT ITS OWN FIXTURE ----------------------------
# This harness creates a disposable git repo and runs `git init` / `git commit` in it.
# Three separate review rounds each found a way for that fixture to escape into the
# REPO UNDER TEST while the harness still printed `pass=.. fail=0`, and one of them
# happened FOR REAL on a developer machine: four junk commits landed on a checked-out
# branch and the clone's local git identity was overwritten. The escapes were:
#
#   1. a failed `mktemp -d` left the path empty, and `cd ""` is a bash no-op, so the
#      fixture ran at the repo root;
#   2. with that guarded, an ambient GIT_DIR — exported inside every git hook and by
#      `git rebase -x`, i.e. an ordinary environment, not a contrived one — redirected
#      the fixture's commits into the repo under test anyway.
#
# So the fixture is now built so that neither is REPRESENTABLE, rather than merely
# guarded against:
#   * nothing in this file `cd`s into a computed path to do git work; every git call
#     names its repo explicitly with `git -C "$repo"` instead — note `git -C ""` is
#     documented as its own no-op, exactly like `cd ""`, so `-C` alone would not have
#     closed escape 1; what actually closes it is the mktemp guard below, which never
#     lets an empty or missing path reach `-C` in the first place;
#   * every git call goes through `sgit`/`gitq`, which strip the repo-redirecting GIT_*
#     variables out of the environment with `env -u`;
#   * `gitq` also pins identity, signing and hooks per-invocation (`-c user.name=…`,
#     `-c commit.gpgsign=false`, `-c core.hooksPath=…`) and neutralises user and system
#     config (`GIT_CONFIG_GLOBAL=/dev/null`), so the fixture never writes git config at
#     all and a global `commit.gpgsign=true` or a blocking `core.hooksPath` hook on the
#     developer's machine cannot turn this file red;
#   * on top of all that the harness REFUSES to start at all when an ambient git
#     environment is present (exit 3), and fingerprints the repo under test before and
#     after its whole run so that a mutation by ANY mechanism — not just the two known
#     ones, and not just inside one child-process window — fails this file.
#
# --- AND WHY THE GUARDS ARE ASSERTED THE WAY THEY ARE -------------------------------
# The same three rounds also found that a guard's own regression test can pass while the
# thing it guards is DELETED. Every probe below therefore asserts the guard's own refusal
# — its exact stderr line and its dedicated exit code — and not merely the consequences
# of the refusal, because consequences can be absent for unrelated reasons (commits
# blocked by a signing config or a pre-commit hook, a renamed file, a `git rev-parse`
# that failed and left both sides of a comparison empty). Consequence assertions are kept
# alongside as a second signal, never as the only one. The static call-site pins are
# anchored at column 0 and require exactly one match, so a commented-out copy of the
# pinned line — this file is ~60% comments — cannot satisfy them. The child-process probe
# is selected by an ARGV flag, not an environment variable, so an ambient variable cannot
# silently switch a block off. And the total number of assertions is pinned at the bottom,
# so a block that is skipped rather than failed still turns this file red.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

# Dedicated exit codes, so a probe can assert the specific refusal it is testing rather
# than "non-zero", which any failed assertion would also produce.
RC_SETUP=2      # cannot locate this file or the template it tests
RC_GITENV=3     # refused: an ambient git environment redirects every git call
RC_MKTEMP=4     # refused: mktemp -d gave no usable scratch directory

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "scripts-executable.test: cannot locate self" >&2; exit "$RC_SETUP"; }
# Derived from "$0", never hardcoded: the child-process probe below re-invokes THIS file,
# and a hardcoded filename would make that probe silently re-invoke nothing (and pass
# vacuously) the day the file is renamed.
SELF="$HERE/$(basename "$0")"
TPL="$(cd "$HERE/.." && pwd)" || { echo "scripts-executable.test: cannot locate template root" >&2; exit "$RC_SETUP"; }
[ -r "$SELF" ] || { echo "scripts-executable.test: cannot read self at $SELF" >&2; exit "$RC_SETUP"; }

# --- guard E: refuse to run inside an ambient git environment -----------------------
# GIT_DIR and friends are exported by git into every hook it runs and by `git rebase -x`,
# so `bash tests/scripts-executable.test.sh` from such a context arrives here with another
# repo already named in the environment. Every unqualified git call in this file —
# including the disposable fixture's `git init` and `git commit` — would then operate on
# THAT repo no matter which directory it is pointed at. That is the original incident
# (junk commits + a clobbered identity in the repo under test), and it is reachable with
# the mktemp guard fully intact, which is why it is refused here rather than merely worked
# around further down. `${!v+set}` tests set-ness, not emptiness: an exported-but-empty
# GIT_DIR is still an ambiguous environment.
GIT_REDIRECT_VARS=(
  GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
)
_ambient=()
for _v in "${GIT_REDIRECT_VARS[@]}"; do
  [[ -n "${!_v+set}" ]] && _ambient+=("$_v")
done
if [[ ${#_ambient[@]} -gt 0 ]]; then
  {
    echo "scripts-executable.test: refusing to run with an ambient git environment (${_ambient[*]})"
    echo "scripts-executable.test: those variables redirect every git command in this file — including the"
    echo "scripts-executable.test: disposable fixture's own 'git init' and 'git commit' — into the repo they"
    echo "scripts-executable.test: name, which is how a fixture lands junk commits in the repo under test."
    echo "scripts-executable.test: re-run with: env $(printf -- '-u %s ' "${GIT_REDIRECT_VARS[@]}")bash $0"
  } >&2
  exit "$RC_GITENV"
fi
unset _ambient _v

# --- the child-process probes are selected by ARGV flags, not env vars --------------
# An environment variable would be inherited from an ambient shell just as GIT_DIR is,
# and an ambient `_SCRIPTS_EXEC_TEST_CHILD=1` used to switch the whole mktemp probe off
# while the summary still read `fail=0`. argv is not inherited, so that cannot happen by
# accident; and the assertion-count pin at the bottom catches it even if it somehow does.
#
# There are two flags because two probes below re-invoke this file, and EITHER flag
# suppresses BOTH probes in the child. That is not tidiness: a child able to re-run the
# probe that spawned it fork-bombs the moment the guard under test is removed — measured,
# by removing the ambient-git-environment refusal and watching the probe recurse until it
# was killed. A guard's regression test must go RED when the guard is deleted, and a hang
# is not red.
MKTEMP_CHILD_FLAG=--mktemp-guard-child
GITENV_CHILD_FLAG=--gitenv-guard-child
IS_CHILD=0
case "${1:-}" in "$MKTEMP_CHILD_FLAG"|"$GITENV_CHILD_FLAG") IS_CHILD=1 ;; esac

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# sgit(): git with the repo-redirecting environment stripped, for READING a repo. Belt
# and braces behind the refusal above — if that refusal is ever weakened, these reads
# still address the repo they name rather than the one the environment names.
GIT_ENV_CLEAN=(env
  -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY
  -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR -u GIT_NAMESPACE
  -u GIT_CONFIG -u GIT_CONFIG_COUNT)
sgit() { "${GIT_ENV_CLEAN[@]}" git "$@"; }

# gitq() <repo> <args…>: git for WRITING a disposable fixture repo. Same sanitised
# environment, plus: user and system config neutralised, identity/signing/hooks supplied
# per-invocation. Consequences — the fixture never runs `git config` (so the identity
# clobber of the original incident is unrepresentable, not merely unlikely), and a
# developer's global `commit.gpgsign=true` or `core.hooksPath` cannot make the fixture
# commits fail and turn this file falsely red.
gitq() {
  local repo="$1"; shift
  "${GIT_ENV_CLEAN[@]}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_TERMINAL_PROMPT=0 \
    git -C "$repo" \
      -c init.defaultBranch=main \
      -c commit.gpgsign=false \
      -c core.hooksPath="$repo/.no-such-hooks" \
      -c user.name=fixture -c user.email=fixture@invalid \
      "$@"
}

# mode_ok(): PASS (echoes "<idx> <head> 0") only when a path is 100755 in BOTH the index
# and the committed HEAD tree of <repo>; otherwise the third field is 1. Run against the
# real template below, and — unchanged — against a disposable fixture repo further down
# that reproduces the exact defect this exists to catch. The same function has to reject
# the fixture or this test proves nothing. Empty fields are printed as "-" so the three
# fields are always present: a missing field used to shift `read -r idx head rc` along by
# one and print the nonsense diagnostic `head=1` while the real rc landed nowhere.
mode_ok() {
  local repo="$1" f="$2" idx head
  idx="$(sgit -C "$repo" ls-files -s -- "$f" 2>/dev/null | awk '{print $1}')"
  head="$(sgit -C "$repo" ls-tree HEAD -- "$f" 2>/dev/null | awk '{print $1}')"
  if [[ "$idx" == 100755 && "$head" == 100755 ]]; then
    printf '%s %s 0\n' "$idx" "$head"
  else
    printf '%s %s 1\n' "${idx:--}" "${head:--}"
  fi
}

# check_group <repo> <label> <min-count> <pathspec> — asserts every matching tracked file
# is 100755 at index AND HEAD, and that at least <min-count> files were actually checked
# (a check over an empty match is a check over nothing).
#
# KNOWN LIMIT, stated rather than implied: enumeration is index-based (`git ls-files`), so
# a path tracked in HEAD but deleted from the INDEX would not be enumerated. That is not
# the working-tree hazard this file is about — it is a deliberate staged deletion — and no
# such path exists here; it is named so the next reader does not mistake index enumeration
# for index+HEAD enumeration. The MODE read (mode_ok) does consult both.
check_group() {
  local repo="$1" label="$2" min="$3" spec="$4"
  local files count=0 f idx head rc
  files="$(sgit -C "$repo" ls-files -- "$spec")"
  assert "there is at least one $label to check" "$([ -n "$files" ] && echo 0 || echo 1)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count+1))
    read -r idx head rc < <(mode_ok "$repo" "$f")
    assert "$f is committed 100755 at index AND HEAD (index=$idx head=$head)" "$rc"
  done <<EOF
$files
EOF
  assert "…and every $label was actually checked ($min or more)" \
    "$([ "$count" -ge "$min" ] && echo 0 || echo 1)"
}

# repo_fingerprint(): everything a stray fixture would disturb in the repo under test —
# the checked-out commit, every ref, the LOCAL git identity, and the working-tree/index
# state. Compared across THIS HARNESS'S WHOLE RUN, not just across one child-process
# window: the earlier version of this probe compared HEAD across the child window only,
# and that window closed before the fixture ran, so it could not see the fixture mutating
# the repo at all. This comparison is mechanism-agnostic — it does not care whether a
# mutation arrived via an empty `cd`, an ambient GIT_DIR, or something nobody has thought
# of yet.
repo_fingerprint() {
  sgit -C "$TPL" rev-parse HEAD 2>/dev/null
  sgit -C "$TPL" show-ref 2>/dev/null
  sgit -C "$TPL" config --local --get-regexp '^user\.' 2>/dev/null
  sgit -C "$TPL" status --porcelain 2>/dev/null
}
FP_BEFORE="$(repo_fingerprint)"

echo "== plugin/scripts — install.sh chmods these on stamp, but the repo itself must be right =="
# The pathspec below is QUOTED and handed to `git ls-files`, not expanded by this shell
# against the working tree. An unquoted `plugin/scripts/*.sh` here would be expanded by
# bash BEFORE check_group ever runs, against whatever happens to exist on disk right now —
# so a file that is committed 100755 but has since been deleted only from the worktree
# (still tracked, still in HEAD) would never even reach `git ls-files` and would silently
# drop out of the check. Quoting routes the pattern through git's own index-backed glob
# matching instead — the one source this test's header already says to trust. See the
# "guard D" reproduction below, and the anchored call-site pin that keeps it quoted.
check_group "$TPL" "plugin/scripts/*.sh" 18 'plugin/scripts/*.sh'

echo "== plugin/hooks — bare paths off settings.json, NO installer chmod at all =="
# 5 -> 4: the three SessionStart hooks became one `session-banner.sh`
# (ai-bridge-v5/task-002), so this directory holds four files, not six. The floor is a
# vacuity guard — "the glob matched something" — not a ceiling, so it moves DOWN with the
# real count rather than being left high enough to pass by luck.
# THE TWO GROUPS BECAME ONE, because the directory they checked became one. `symlink/`
# held the SessionStart banner and the UserPromptSubmit push-state hook; both moved to
# `plugin/hooks/` beside `deny-destructive.sh` and `agent-control.sh` when the bundle
# stopped carrying machinery (ai-bridge-v2/task-013). Four files, one group, and the pin
# below counts ONE call site — two identical calls would pass while checking one thing.
echo "== plugin/hooks — invoked straight off hooks.json, and NOTHING chmods these ever =="
# THE EXPOSURE IS STRICTLY WORSE HERE THAN IN EITHER GROUP ABOVE, which is why the two
# hooks that moved needed their own group rather than being dropped from the check. A
# `plugin/scripts` file at least passes through install.sh's `chmod +x` on every stamp; a
# `plugin/hooks` file does not, but at least an installer runs against it. A
# plugin hook is fetched by the plugin loader and invoked by absolute path straight out of
# `hooks.json` — there is no installer in that path at all, so a committed-644 file here is
# a 126 on every single tool call in every session on the machine, with nothing to launder
# it on any developer's disk.
check_group "$TPL" "plugin/hooks/*.sh" 4 'plugin/hooks/*.sh'

if [[ $IS_CHILD -eq 0 ]]; then
  echo "== guard C: a failed 'mktemp -d' must ABORT with its own refusal line, not run the fixture in place =="
  # Regression test for a real incident shape: if `mktemp -d` fails (e.g. a bogus or
  # unwritable TMPDIR) and the result is used unguarded, `FIX=""` and `cd "$FIX"` SUCCEEDS
  # without moving (bash treats `cd ""` as a no-op), so every "disposable fixture" command
  # runs at the repo root of the real checkout under test. Re-invoke this same file as a
  # child with a TMPDIR that cannot be created under, and require the REFUSAL ITSELF.
  #
  # WHY THE REFUSAL LINE AND EXIT CODE, NOT JUST THE CONSEQUENCES. An earlier version of
  # this probe asserted only consequences — "no clean summary", "HEAD did not move" — and
  # passed with the guard DELETED in three separate situations: when the fixture's commits
  # could not land anyway (a global commit.gpgsign, or a blocking pre-commit hook), when
  # this file had been renamed so the child re-invoked nothing, and when `git rev-parse`
  # failed and left both sides of the HEAD comparison empty and therefore equal. Asserting
  # the guard's own stderr line and its dedicated exit code cannot pass by accident: those
  # only appear if the guard ran and refused.
  MKTEMP_REFUSAL='scripts-executable.test: mktemp -d failed; refusing to run the fixture in place'
  BOGUS_TMPDIR="/nonexistent-scripts-exec-fixture-guard-$$"
  BEFORE_HEAD="$(sgit -C "$TPL" rev-parse HEAD 2>/dev/null || true)"
  assert "the probe's own HEAD read produced a real sha (two empty sides would compare equal and prove nothing)" \
    "$([[ "$BEFORE_HEAD" =~ ^[0-9a-f]{40}$ ]] && echo 0 || echo 1)"
  GUARD_OUT="$(TMPDIR="$BOGUS_TMPDIR" bash "$SELF" "$MKTEMP_CHILD_FLAG" 2>&1)"
  GUARD_RC=$?
  AFTER_HEAD="$(sgit -C "$TPL" rev-parse HEAD 2>/dev/null || true)"
  assert "a failed mktemp -d prints the guard's own refusal line verbatim" \
    "$(grep -qF "$MKTEMP_REFUSAL" <<<"$GUARD_OUT" && echo 0 || echo 1)"
  assert "…and exits with the dedicated code $RC_MKTEMP, not merely non-zero (got $GUARD_RC)" \
    "$([ "$GUARD_RC" -eq "$RC_MKTEMP" ] && echo 0 || echo 1)"
  assert "…and never prints a clean pass=.. fail=0 summary" \
    "$(grep -Eq '^pass=[0-9]+ fail=0$' <<<"$GUARD_OUT" && echo 1 || echo 0)"
  assert "…and the repo under test gained no commits from a fixture running at its root" \
    "$([ "$BEFORE_HEAD" == "$AFTER_HEAD" ] && echo 0 || echo 1)"
fi

echo "== the disposable fixture: create a scratch repo, or refuse to run at all =="
# A disposable repo reproducing the exact defect this test exists to catch: committed at
# 100644, then `git update-index --chmod=+x` staged (NOT committed) on top — the exact
# command close-project-folder.sh was fixed with, stopped one step short of a commit. An
# index-only read says PASS here; mode_ok() must say FAIL.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/scripts-exec-fixture.XXXXXX")" || {
  echo "scripts-executable.test: mktemp -d failed; refusing to run the fixture in place" >&2
  exit "$RC_MKTEMP"
}
if [[ -z "$FIX" || ! -d "$FIX" ]]; then
  echo "scripts-executable.test: mktemp -d failed; refusing to run the fixture in place" >&2
  echo "scripts-executable.test: (it returned an empty or non-directory path: '$FIX')" >&2
  exit "$RC_MKTEMP"
fi
trap 'rm -rf "$FIX"' EXIT

if [[ $IS_CHILD -eq 0 ]]; then
  echo "== guard E: an ambient GIT_DIR must make this harness REFUSE, not commit into the repo it names =="
  # The incident class fix C did NOT close. With the mktemp guard fully intact, an ambient
  # GIT_DIR made the fixture commit into the repo under test — four junk commits and an
  # overwritten identity — while the harness printed `pass=38 fail=0`. GIT_DIR is exported
  # inside every git hook and by `git rebase -x`, so that is an ordinary environment.
  #
  # The decoy below stands in for "the repo under test" so this can be proved without going
  # anywhere near a real checkout: point GIT_DIR at the decoy, re-invoke this file, and
  # require the refusal (exact line, dedicated exit code) AND the decoy's untouched state.
  # The refusal assertions are the load-bearing ones — the decoy-untouched pair would also
  # hold if the fixture simply failed to commit for some unrelated reason, so they are a
  # second signal, not the signal.
  DECOY="$FIX/decoy"
  mkdir -p "$DECOY"
  gitq "$DECOY" init -q .
  printf 'seed\n' > "$DECOY/seed.txt"
  gitq "$DECOY" add seed.txt >/dev/null
  gitq "$DECOY" commit -qm "decoy seed" >/dev/null
  DECOY_HEAD_BEFORE="$(gitq "$DECOY" rev-parse HEAD 2>/dev/null || true)"
  DECOY_COUNT_BEFORE="$(gitq "$DECOY" rev-list --count HEAD 2>/dev/null || echo -1)"
  assert "the decoy repo really was seeded with exactly 1 commit (or the checks below compare nothing)" \
    "$([ "$DECOY_COUNT_BEFORE" == 1 ] && echo 0 || echo 1)"

  GITENV_OUT="$(GIT_DIR="$DECOY/.git" bash "$SELF" "$GITENV_CHILD_FLAG" 2>&1)"
  GITENV_RC=$?
  DECOY_HEAD_AFTER="$(gitq "$DECOY" rev-parse HEAD 2>/dev/null || true)"
  DECOY_COUNT_AFTER="$(gitq "$DECOY" rev-list --count HEAD 2>/dev/null || echo -2)"

  assert "an ambient GIT_DIR makes the harness print its own refusal line verbatim" \
    "$(grep -qF 'scripts-executable.test: refusing to run with an ambient git environment' <<<"$GITENV_OUT" && echo 0 || echo 1)"
  assert "…and the refusal names the offending variable (GIT_DIR) so the caller can act on it" \
    "$(grep -qF 'ambient git environment (GIT_DIR)' <<<"$GITENV_OUT" && echo 0 || echo 1)"
  assert "…and exits with the dedicated code $RC_GITENV, not merely non-zero (got $GITENV_RC)" \
    "$([ "$GITENV_RC" -eq "$RC_GITENV" ] && echo 0 || echo 1)"
  assert "…and the repo GIT_DIR named gained no commits ($DECOY_COUNT_BEFORE -> $DECOY_COUNT_AFTER)" \
    "$([ "$DECOY_COUNT_BEFORE" == "$DECOY_COUNT_AFTER" ] && echo 0 || echo 1)"
  assert "…and its HEAD did not move" \
    "$([ -n "$DECOY_HEAD_BEFORE" ] && [ "$DECOY_HEAD_BEFORE" == "$DECOY_HEAD_AFTER" ] && echo 0 || echo 1)"
fi

echo "== the guard itself: does it catch the reproduction, not just today's repo state? =="
gitq "$FIX" init -q .

printf '#!/usr/bin/env bash\necho hi\n' > "$FIX/bad.sh"
gitq "$FIX" add bad.sh >/dev/null
gitq "$FIX" commit -qm "committed at 644" >/dev/null   # HEAD tree: 100644
chmod +x "$FIX/bad.sh"
gitq "$FIX" update-index --chmod=+x bad.sh             # index only: 100755, HEAD unchanged

read -r idx head rc < <(mode_ok "$FIX" bad.sh)
assert "naive index-only read of the reproduction says 100755 (the bug being fixed)" \
  "$([ "$idx" == 100755 ] && echo 0 || echo 1)"
assert "…but HEAD is still 100644, so HEAD=100644/INDEX=100755 now FAILS ($idx/$head)" \
  "$([ "$rc" == 1 ] && echo 0 || echo 1)"

# Undo bad.sh's staged-but-uncommitted chmod before touching good.sh, so the next commit
# cannot sweep bad.sh's mode change in along with it — each file's fixture state must stay
# isolated or the next assertion proves nothing.
gitq "$FIX" reset -q HEAD -- bad.sh
printf '#!/usr/bin/env bash\necho ok\n' > "$FIX/good.sh"
chmod +x "$FIX/good.sh"
gitq "$FIX" add good.sh >/dev/null
gitq "$FIX" update-index --chmod=+x good.sh
gitq "$FIX" commit -qm "committed at 755" >/dev/null   # HEAD and index both: 100755

read -r idx head rc < <(mode_ok "$FIX" good.sh)
assert "a genuinely committed-755 file still PASSES at index and HEAD" "$rc"

echo "== guard D: a file committed 755 then deleted only from the worktree must still be enumerated =="
# Regression test for check_group's file-list source, not just mode_ok()'s file-mode read.
# A 16th script committed at 755 and then `rm`ed from disk only (still tracked at 100755 in
# the index and HEAD) reproduces the exact defect an unquoted call-site glob had: bash
# expands `d-*.sh` against the working tree BEFORE git ever sees it, so the
# deleted-but-tracked file never reaches `git ls-files` at all — the min-count floor does
# not save it because the other on-disk file(s) still clear it. Quoting the pattern (this
# test's real fix, applied to the two check_group calls above) routes enumeration through
# git's index instead.
printf '#!/usr/bin/env bash\necho good\n' > "$FIX/d-good.sh"
chmod +x "$FIX/d-good.sh"
gitq "$FIX" add d-good.sh >/dev/null
gitq "$FIX" update-index --chmod=+x d-good.sh
gitq "$FIX" commit -qm "committed 755, stays on disk" >/dev/null

printf '#!/usr/bin/env bash\necho gone\n' > "$FIX/d-gone.sh"
chmod +x "$FIX/d-gone.sh"
gitq "$FIX" add d-gone.sh >/dev/null
gitq "$FIX" update-index --chmod=+x d-gone.sh
gitq "$FIX" commit -qm "committed 755, then removed from the worktree only" >/dev/null
rm -f "$FIX/d-gone.sh"   # tracked 100755 at index+HEAD; absent from the working tree

# Mimics exactly what an unquoted call site does: bash expands the glob into positional
# args itself, before anything downstream ever runs — no `ls`/subprocess glob involved.
UNQUOTED_COUNT="$(
  cd "$FIX" || exit 1
  shopt -s nullglob
  files=(d-*.sh)
  echo "${#files[@]}"
)"
GIT_COUNT="$(sgit -C "$FIX" ls-files -- 'd-*.sh' | wc -l | tr -d ' ')"
assert "an unquoted shell glob only sees the file still present on disk (the old bug shape)" \
  "$([ "$UNQUOTED_COUNT" == 1 ] && echo 0 || echo 1)"
assert "…but 'git ls-files' against the quoted pattern finds both, straight from the index" \
  "$([ "$GIT_COUNT" == 2 ] && echo 0 || echo 1)"

check_group "$FIX" "fixture d-*.sh (quoted call site, the fixed shape)" 2 'd-*.sh'

echo "== guard G: the three real call sites above must stay quoted — and stay CALLS, not comments =="
# The fixture above proves quoting matters in principle; this proves it is actually applied
# where it counts. Today's real repo has no worktree-deleted-but-tracked script, so an
# unquoted call site would not fail the checks above by itself — this static pin is what
# catches someone reverting the quoting on the real check_group calls.
#
# WHY ANCHORED, AND WHY EXACTLY ONE MATCH. The first version used an unanchored `grep -qF`
# over a file that is ~60% comments, so reverting the quoting by commenting the real call
# out and pasting an unquoted copy below it PASSED — the commented-out original still
# contained the pinned string. `^…$` at column 0 excludes any commented or indented copy,
# and requiring exactly one match excludes a second copy hiding elsewhere. The min-count
# argument is matched as `[0-9]+` rather than as a literal, so raising the floor when a
# 16th script is added is an ordinary edit and not a false "no longer quoted" failure.
pin_count() { grep -cE "$1" "$SELF" 2>/dev/null || true; }
# The patterns below are regexes, not strings to expand — single quotes are deliberate.
# shellcheck disable=SC2016
assert "the plugin/scripts/*.sh check_group call is a real, quoted call at column 0 (exactly one)" \
  "$([ "$(pin_count '^check_group "\$TPL" "plugin/scripts/\*\.sh" [0-9]+ .plugin/scripts/\*\.sh.$')" == 1 ] && echo 0 || echo 1)"
# shellcheck disable=SC2016
# shellcheck disable=SC2016
assert "the plugin/hooks/*.sh check_group call is a real, quoted call at column 0 (exactly one)" \
  "$([ "$(pin_count '^check_group "\$TPL" "plugin/hooks/\*\.sh" [0-9]+ .plugin/hooks/\*\.sh.$')" == 1 ] && echo 0 || echo 1)"
# The two pins above cover the CALL sites, not check_group's own USE of $spec at its one
# call to `ls-files`. That gap is real, not theoretical: unquoting `$spec` there (`--
# $spec` instead of `-- "$spec"`) still leaves this whole file at 49/49 today, because
# neither call site's pathspec currently contains anything a shell would expand
# differently once split — guard D's own fixture glob (`d-*.sh`) never reaches this line
# unquoted-and-unmatched in a cwd that would change its outcome. So the inner use site
# needs its own anchored pin, exactly like the call sites above, or a future edit can
# unquote it with nothing here going red.
# shellcheck disable=SC2016
assert "check_group's own ls-files call keeps \$spec quoted at its use site (exactly one)" \
  "$([ "$(pin_count '^  files="\$\(sgit -C "\$repo" ls-files -- "\$spec"\)"$')" == 1 ] && echo 0 || echo 1)"

echo "== the repo under test must be exactly as this harness found it =="
FP_AFTER="$(repo_fingerprint)"
if [[ "$FP_BEFORE" != "$FP_AFTER" ]]; then
  echo "scripts-executable.test: the repo under test CHANGED while this harness ran:" >&2
  diff <(printf '%s\n' "$FP_BEFORE") <(printf '%s\n' "$FP_AFTER") >&2 || true
fi
assert "the repo under test is unchanged: HEAD, every ref, the local identity and the worktree state" \
  "$([ "$FP_BEFORE" == "$FP_AFTER" ] && echo 0 || echo 1)"
assert "…and that fingerprint is non-empty, so the comparison above is not two blanks compared equal" \
  "$([ -n "$FP_BEFORE" ] && echo 0 || echo 1)"

# --- guard H: pin the assertion total ------------------------------------------------
# An ambient variable used to switch the mktemp probe off entirely: three assertions
# vanished, `fail=0` either way, and nothing anywhere said how many were supposed to run.
# A skipped block is now as red as a failed one. The pin counts every assertion BEFORE
# itself; add or remove an assertion and this number moves with it, deliberately, in the
# same commit.
# 54 -> 55: plugin/hooks/deny-destructive.sh (ai-bridge-v5/task-006) is one more
# executable machinery file, so the per-file enumeration runs one more assertion.
# 55 -> 56: plugin/scripts/tick-lock.sh (ai-bridge-v5/task-003), same reason.
# 56 -> 55: ai-bridge-v5/task-002 nets one file OFF the enumeration — `resolve-config.sh`
# is new (+1) while `check-machinery.sh`, `show-awaiting.sh` and `show-board-link.sh`
# became one `session-banner.sh` (-2).
# 55 -> 56: plugin/scripts/pr-body-clearance.sh (ai-bridge-v5/task-005), same reason.
# 56 -> 57: plugin/scripts/check-template-version.sh (ai-bridge-v5/task-008), one more
# executable machinery file in the per-file enumeration.
# 57 -> 58: plugin/scripts/ai-bridge.sh (ai-bridge-v5/task-011), same reason.
# 58 -> 59: plugin/scripts/pr-comment-clearance.sh (ai-bridge-v5/task-026), one more
# executable machinery file in the per-file enumeration.
# 60 -> 63: ai-bridge-v2/task-003 moves `deny-destructive.sh` and `agent-control.sh` from
# `plugin/hooks/` to `plugin/hooks/`. Net +3, and it is worth spelling out because
# a move is the one shape where the arithmetic is not obvious: -2 files leave the old
# group's per-file enumeration, +4 arrive with the new group (its vacuity guard, its two
# files, its min-count), and +1 is the new group's anchored call-site pin.
EXPECTED_ASSERTIONS=62
TOTAL=$((pass + fail))
# EXPECTED_ASSERTIONS is a running counter whose comment history is longer than the value
# it annotates, so a merge can plausibly keep the annotations and lose the assignment —
# which is exactly what merging main into ai-bridge-v5/task-005 did. Without this guard
# the next read aborts under `set -u` with a bash line number and no summary line, and the
# suite wrapper reports an opaque harness crash. Name the variable instead. The guard sits
# at the first READ rather than beside `set -uo pipefail`, because the assignment lives at
# the bottom of the file with the history it belongs to: at the top it would refuse every
# run.
: "${EXPECTED_ASSERTIONS:?EXPECTED_ASSERTIONS not set — a merge likely dropped it}"
assert "exactly $EXPECTED_ASSERTIONS assertions ran — a silently skipped block shows up here (got $TOTAL)" \
  "$([ "$TOTAL" -eq "$EXPECTED_ASSERTIONS" ] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
