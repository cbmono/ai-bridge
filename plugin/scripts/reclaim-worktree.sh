#!/usr/bin/env bash
#
# reclaim-worktree.sh — remove ONE task's worktree, named by the task itself.
#
#   Usage: reclaim-worktree.sh <task-path>              # verify, then remove
#          reclaim-worktree.sh --dry-run <task-path>    # verify only, remove nothing
#
# Exit codes:
#
#   0  removed (with --dry-run: every guard passed, nothing was touched)
#   1  REFUSED — a guard failed. Report it to the human; do not retry around it.
#   2  cannot answer: usage error, not an instance root, unreadable frontmatter
#   3  nothing to do: the task records no worktree, or the recorded path is
#      already gone. Silence, never an error — this is the idempotent re-run.
#
# WHY THIS EXISTS SEPARATELY FROM prune-worktrees.sh, WHICH MUST NEVER DELETE.
# The pruner SCANS a directory and INFERS which worktrees are finished. That
# inference destroyed three running agents' worktrees (2026-08-04) and its delete
# path was removed for good; it stays report-only, and no flag brings it back.
# Every one of those incidents came from the same place — a guess:
#
#   1. ZERO-COMMIT AMBIGUITY. A fresh dispatch that has not committed yet is
#      identical in git to an already-merged branch. There is no discriminator.
#   2. NAME MATCHING. `gh pr list --head <branch>` matches by branch NAME, so a
#      recycled name carried an old merged PR onto a live worktree.
#   3. DETACHED HEAD. Commits on no ref, so removal destroyed their only
#      reachability (HEAD plus the per-worktree reflog).
#
# This script guesses at none of that, because the TASK is authoritative where
# the scan was guessing. The dispatching PM chose the worktree path and the
# branch, wrote both into the task (`worktree:` / `branch:`), and set the task
# `done` only after checking that every URL in `pr:` had merged. So:
# finished-ness comes from PR URLs (immune to name matching) and from a status the
# PM set deliberately (immune to the zero-commit ambiguity), and the identity of
# the directory comes from a record rather than from a directory listing.
#
# It follows that the ONE thing this script must never do is drift back toward
# inference. There is no scan here, no candidate list, no "all finished
# worktrees" mode. One task, one recorded path, one removal — and if the task
# names no worktree, the answer is to do nothing (exit 3), never to go looking.
#
# THE GUARDS ARE THE DELIVERABLE. Removal happens only when every one passes;
# any failure, and anything this script cannot establish, is a refusal that
# reports. In evaluation order, and each one says what it is paid for:
#
#   G1  the task's frontmatter is readable                          (else exit 2)
#   G2  `status:` is exactly `done`. Not `cancelled`: the authority for deleting
#       anything here is "the PM proved every PR merged", and a cancelled task
#       proved the opposite — its PR was closed unmerged, so that worktree may
#       hold the only copy of the work. Report it for a human instead.
#   G3  `worktree:` is recorded — else exit 3, do nothing. And if `worktree:` is
#       recorded while `branch:` is NOT, that is a REFUSAL, not a licence to skip
#       the branch check: the branch is how identity is established (G8), and a
#       missing guard input must never read as a passed guard.
#   G4  the recorded path is absolute, contains no `..`, exists (else exit 3 —
#       already reclaimed), and resolves INSIDE this instance's worktree roots:
#       `worktreeRoot` from instance.config.json, or the legacy `<reposRoot>/_wt`
#       when that key is absent (both are accepted, because a dispatch on an
#       older instance landed in the legacy one). A task document is text a human
#       and several agents edit, so the path in it is checked against config
#       rather than trusted — an absolute path from a text file is otherwise a
#       delete-anything primitive.
#   G5  `target_repo:` is recorded and `<reposRoot>/<repo>` is a git repo. The
#       "expected repo" is not inferred from the worktree; it comes from the task.
#   G6  the path is a REGISTERED worktree of that repo, and is not the repo's own
#       main working tree. An unregistered directory (a rescued tree, a hand-made
#       copy, a cache dir) is somebody's, and not ours to delete.
#   G7  the worktree is not LOCKED. `git worktree lock` is an explicit "do not
#       touch" and it is honoured, exactly as in the pruner.
#   G8  it is NOT detached, and its current branch EQUALS the recorded `branch:`.
#       Two guards for two different incidents. Detached: a removal deletes the
#       only reachability those commits have, so it is refused unconditionally
#       and reported for a human to rescue with `git branch <name> <sha>` — no
#       flag, no override, however certain the record looks. Branch equality: a
#       PATH can be recycled (removed, then re-created for another task), and the
#       recorded branch is what tells a recycled path from the one this task
#       created. Note what closes the remaining corner, where a later task
#       reuses BOTH the same path and the same branch name: a re-dispatch of the
#       SAME task moves it off `done`, so G2 refuses; and a DIFFERENT task
#       reusing both names is refused by G12 while it is live. Dispatch-time
#       naming keeps the two apart in the first place (project slug + task id).
#   G9  the tree is CLEAN — `git status --porcelain` empty. No allowance for
#       "recognised scaffolding" as in the pruner's REPORT: this path deletes, so
#       any modification and any untracked file refuses. A manual sweep once
#       found 88 lines of uncommitted README work in a "finished" worktree.
#   G10 NOTHING IS UNPUSHED: every commit reachable from HEAD is reachable from
#       some remote-tracking ref (`rev-list --count HEAD --not --remotes` == 0).
#       This covers both merge strategies where the ref survives — a merge-commit
#       repo has the tip in origin/<default>, a squash-merge repo still has the
#       branch's own commits on origin/<branch>. Where the remote branch was
#       deleted on merge AND the local clone has pruned it, the count is non-zero
#       and this REFUSES. That is the documented cost, in the safe direction: the
#       human sees a report line instead of a script deciding that commits it
#       cannot find anywhere are expendable.
#   G11 every URL in `pr:` is MERGED, checked BY URL through `gh pr view` — never
#       by branch, which is guard 2's whole lesson. An empty `pr:` refuses (a
#       build task cannot have finished without one). No `gh`, an auth failure, a
#       network error, or a state this script does not recognise all refuse:
#       an unknown must never be what authorises a deletion. At least one of the
#       URLs must belong to `target_repo`, so a task whose only merged PR is in
#       some other repo cannot clear this repo's worktree.
#   G12 RECENTLY ACTIVE — nothing inside the worktree has been touched within
#       PRUNE_ACTIVE_MINUTES (default 120, same knob and same default as the
#       pruner). The walk is RECURSIVE for a measured reason: an agent editing
#       `src/**` never changes the worktree ROOT's mtime, so a root-only check
#       ages a live agent out of the window (39 ms on a 664 MB repo). It runs
#       last because it is the only guard that is a matter of TIME rather than of
#       fact — refusing here means "ask again on a later tick", and the caller
#       needs to be able to tell that from a refusal that will never clear.
#
# NO --force, EVER. `git status --porcelain` does not see ignored files, so a
# worktree whose only remaining content is an ignored `.env` or a local config
# passes G9 — and `--force` would delete it. Plain `git worktree remove` refuses
# instead, which is the property to preserve: the last word on an ignored file
# belongs to the human who put it there. A refusal from git is reported as a
# refusal from this script.
#
# WHAT A MIS-IDENTIFICATION COSTS, stated honestly, because it is the real bound.
# G8+G9+G10 mean every removal is of a branch-attached worktree with nothing
# uncommitted and nothing unpushed. So even a worktree removed in error costs a
# checkout, never work: the branch ref survives (removal deletes the working
# directory and the admin entry, not the branch), and every commit is on a remote.
# The classes whose loss would be irrecoverable — detached HEADs, unpushed
# commits, uncommitted files — are exactly the three this script refuses.
#
# THE VERIFY-AFTER-WRITE RULE. A claimed removal is checked on disk afterwards. A
# false success is worse than the error it claims to fix (migrate-bundle.sh
# shipped exactly that bug once): a report of "removed" for a directory that is
# still there sends the next tick past a worktree nobody will look at again.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/reclaim-worktree.test.sh, which builds real repos and
# worktrees under mktemp and asserts one refusal per guard above (plus the
# positive case). Run it after any change here — like the pruner, this script
# cannot be exercised safely by hand.
set -uo pipefail

CONFIG="instance.config.json"
LOCAL_CONFIG="instance.config.local.json"
SELF="$(basename "$0")"

usage() {
  echo "Usage: $SELF [--dry-run] <task-path>" >&2
  exit 2
}

DRY=0
TARGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$TARGET" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || usage

# Report shapes. `refuse:` is the only one that means "a guard said no"; keep the
# word stable, callers and the test harness grep for it.
refuse() { printf 'refuse: %s\n' "$*" >&2; exit 1; }
noop()   { printf 'noop: %s\n' "$*"; exit 3; }
fatal()  { printf 'error: %s\n' "$*" >&2; exit 2; }

[ -f SCHEMA.md ] && [ -f "$CONFIG" ] \
  || fatal "run from a control-panel instance root (SCHEMA.md + $CONFIG)."

# --- readers -----------------------------------------------------------------

# Portable extraction of a JSON string value (no jq dependency) — the same parse
# task-owner.sh and commit-as.sh use. A missing file is silence, not an error.
json_string() { # <file> <key>
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# An OVERRIDABLE path key, local file winning over the tracked one, with a
# leading ~ expanded. `reposRoot` and `worktreeRoot` are absolute paths on THIS
# machine, so on a bundle shared by two humans the tracked value cannot be right
# for both. The full overridable set is documented in ONE place: SCHEMA.md →
# "Per-machine config overrides".
config_path() { # <key>
  local v
  v="$(json_string "$LOCAL_CONFIG" "$1")"
  [ -n "$v" ] || v="$(json_string "$CONFIG" "$1")"
  printf '%s' "${v/#\~/$HOME}"
}

# Resolve symlinks, because `git worktree list --porcelain` prints resolved
# paths: comparing an unresolved path against them matches nothing, and on macOS
# $TMPDIR alone ($TMPDIR -> /private/var/...) is enough to trigger it. This trap
# has appeared three times in this codebase.
canon() { ( cd "$1" 2>/dev/null && pwd -P ); }

# Print the frontmatter block. Exit 3 when the file does not open with `---`,
# exit 4 when it opens but never closes — the same reader validate-bundle.sh and
# task-owner.sh use, for the same reason: an unterminated block would return the
# whole file, and a `branch:` line in the BODY (prose, a note, a quoted example)
# would then be read as frontmatter.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# The FIRST occurrence of a scalar key only. A document with the key repeated
# would otherwise be judged from the LATER value — the bug push-state.sh had with
# `status:`. An empty value reads as absent. awk rather than `sed | head`: the
# reader consumes its whole input, so no early-exiting stage can SIGPIPE the one
# before it under `pipefail`.
fm_scalar() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
    !got && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*$/, "", v)
      sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# Every http(s) URL under a list key, whether it is written inline
# (`pr: [ a, b ]`) or as a block list (`pr:` then `  - a`). Collect the key's own
# line plus every following line that is indented or a list item, stopping at the
# next top-level key, then pull the URLs out of that slice. Shape-tolerant on
# purpose: the PM and the role agents both append here, and this must not be a
# second YAML dialect to get wrong.
fm_list_urls() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
      index($0, k ":") == 1 { grab = 1; print; next }
      grab && /^[[:space:]]/ { print; next }
      grab && /^-/ { print; next }
      grab { grab = 0 }
    ' | grep -oE 'https?://[^][:space:],"'"'"']+' || true
}

# --- G1: the task document ---------------------------------------------------

tdir="$(dirname "$TARGET")"
[ -d "$tdir" ] || fatal "no such task document: $TARGET"
abs="$(cd "$tdir" && pwd -P)/$(basename "$TARGET")"
root="$(pwd -P)"

# The task document must live under THIS instance's projects/. Without this the prefix
# strip below silently leaves `rel` absolute for a path outside the instance, and every
# later guard then reads an attacker-chosen file: a `done` task carrying a matching
# `worktree:`, `branch:`, `target_repo:` and a merged PR URL would pass all of them and
# remove a clean, registered worktree this instance never dispatched. The authority for
# deleting a worktree is *this bundle's own record of having created it*, so a document
# from anywhere else is not evidence, however well-formed it looks.
#
# Compared canonically (`pwd -P` both sides) because /var vs /private/var on macOS makes
# two spellings of one path — the trap that has already broken task-owner.sh and
# codegraph-sync.sh in this codebase.
case "$abs" in
  "$root"/projects/*) ;;
  *) fatal "$TARGET is not a task document of this instance.
       Expected a path under $root/projects/ — got $abs.
       Refusing: the record that authorises removing a worktree has to be this
       bundle's own." ;;
esac

rel="${abs#"$root"/}"
[ -f "$rel" ] || fatal "no such task document: $TARGET"

fm=""; rc=0
fm="$(fm_block "$rel")" || rc=$?
[ "$rc" -eq 0 ] || fatal "$rel has no readable YAML frontmatter — refusing rather than
       reading a body line as a field."

STATUS="$(fm_scalar "$fm" status)"
WT_REC="$(fm_scalar "$fm" worktree)"
BR_REC="$(fm_scalar "$fm" branch)"
REPO_REC="$(fm_scalar "$fm" target_repo)"

# --- G2: the task must be done -----------------------------------------------

[ "$STATUS" = "done" ] || refuse "$rel is '${STATUS:-<none>}', not 'done' — only a done task
        has had every PR checked as merged, which is the whole authority for
        removing anything here. A cancelled task's PR was closed UNMERGED, so its
        worktree may hold the only copy of that work: report it, never remove it."

# --- G3: what the task records -----------------------------------------------

[ -n "$WT_REC" ] || noop "$rel records no 'worktree:' — nothing to reclaim. (This script
      never goes looking for one: no record, no removal.)"

[ -n "$BR_REC" ] || refuse "$rel records worktree '$WT_REC' but no 'branch:'. The recorded
        branch is how a recycled path is told from the one this task created, so a
        missing branch is a missing guard, not a guard that passed."

# --- G4: the path is one of ours ---------------------------------------------

case "$WT_REC" in
  /*) ;;
  *) refuse "recorded worktree '$WT_REC' is not an absolute path." ;;
esac
case "$WT_REC" in
  *..*) refuse "recorded worktree '$WT_REC' contains '..' — refusing to resolve it." ;;
esac

[ -d "$WT_REC" ] || noop "recorded worktree '$WT_REC' does not exist — already reclaimed."

WT="$(canon "$WT_REC")"
[ -n "$WT" ] || refuse "cannot resolve recorded worktree '$WT_REC'."

REPOS_ROOT="$(config_path reposRoot)"
[ -n "$REPOS_ROOT" ] && [ -d "$REPOS_ROOT" ] \
  || fatal "reposRoot ('$REPOS_ROOT') not found — check $LOCAL_CONFIG / $CONFIG."
REPOS_ROOT="$(canon "$REPOS_ROOT")"

# The configured root, and the legacy `<reposRoot>/_wt` for instances whose
# config predates the key. Every doc naming `worktreeRoot` must state that
# fallback, and so must this one.
ROOTS=""
WT_CONFIGURED="$(config_path worktreeRoot)"
if [ -n "$WT_CONFIGURED" ] && [ -d "$WT_CONFIGURED" ]; then
  ROOTS="$(canon "$WT_CONFIGURED")"
fi
if [ -d "$REPOS_ROOT/_wt" ]; then
  ROOTS="$ROOTS
$(canon "$REPOS_ROOT/_wt")"
fi

inside_a_root=1
while IFS= read -r r; do
  [ -n "$r" ] || continue
  case "$WT/" in "$r"/*/) inside_a_root=0 ;; esac
done <<EOF
$ROOTS
EOF
[ "$inside_a_root" -eq 0 ] || refuse "$WT is not inside this instance's worktree roots
        (worktreeRoot from $CONFIG, or the legacy <reposRoot>/_wt when that key is
        absent). A path out of a text document is checked against config, never
        trusted."

# --- G5: the expected repo comes from the task -------------------------------

[ -n "$REPO_REC" ] || refuse "$rel records no 'target_repo:', so the repo this worktree
        should belong to cannot be established from the task."
REPO_DIR="$REPOS_ROOT/${REPO_REC##*/}"
[ -e "$REPO_DIR/.git" ] || refuse "expected repo '$REPO_REC' is not cloned at $REPO_DIR."
REPO_CANON="$(canon "$REPO_DIR")"

# --- G6/G7/G8: what git says about that exact path ---------------------------
# Parse `worktree list --porcelain` rather than asking the worktree what branch it
# is on: the porcelain reports `detached` explicitly, where `rev-parse
# --abbrev-ref HEAD` returns the literal string "HEAD" and invites exactly the
# branch-shaped comparison that can never match.
#
# ONE pass, with an in-record flag rather than blank-line record boundaries: a
# here-doc drops trailing newlines, so a boundary-driven parse has to special-case
# the LAST record — which is exactly the record most likely to be the one being
# reclaimed. A field line belongs to the `worktree ` line above it, and that is
# all the state needed.
found=1; is_main=1; detached=0; locked=0; prunable=0; branch=""; head=""
seen=0; in_rec=1
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      cur="${line#worktree }"; seen=$((seen + 1))
      if [ "$cur" = "$WT" ] || [ "$(canon "$cur" 2>/dev/null)" = "$WT" ]; then
        in_rec=0; found=0
        [ "$seen" -eq 1 ] && is_main=0
      else
        in_rec=1
      fi ;;
    "HEAD "*)   [ "$in_rec" -eq 0 ] && head="${line#HEAD }" ;;
    "branch "*) [ "$in_rec" -eq 0 ] && { branch="${line#branch }"; branch="${branch#refs/heads/}"; } ;;
    detached)              [ "$in_rec" -eq 0 ] && detached=1 ;;
    locked|"locked "*)     [ "$in_rec" -eq 0 ] && locked=1 ;;
    prunable|"prunable "*) [ "$in_rec" -eq 0 ] && prunable=1 ;;
  esac
done <<EOF
$(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null)
EOF

[ "$found" -eq 0 ] || refuse "$WT is not a registered worktree of $REPO_REC ($REPO_DIR).
        An unregistered directory is somebody's — a rescued tree, a hand-made
        copy, a cache dir — and not ours to delete."
[ "$is_main" -eq 1 ] || refuse "$WT is the MAIN working tree of $REPO_REC, not a worktree
        of it."
[ "$WT" != "$REPO_CANON" ] || refuse "$WT is the repo itself."
[ "$prunable" -eq 0 ] || refuse "$WT is registered but git calls it prunable — a human
        should look before anything is removed."
[ "$locked" -eq 0 ] || refuse "$WT is LOCKED. 'git worktree lock' is an explicit 'do not
        touch' and it is honoured here."
[ "$detached" -eq 0 ] || refuse "$WT is at a DETACHED HEAD (${head:0:8}). Its commits are
        reachable only from that HEAD and the per-worktree reflog, both of which
        'git worktree remove' deletes — so this is refused unconditionally, with
        no flag to override it. Rescue it first:
          git -C $REPO_DIR branch <name> $head"
[ "$branch" = "$BR_REC" ] || refuse "$WT is on branch '${branch:-<none>}' but $rel recorded
        '$BR_REC'. A worktree PATH can be recycled for another task; the recorded
        branch is what tells that apart from the worktree this task created."

# --- G9: nothing uncommitted -------------------------------------------------

st="$(git -C "$WT" status --porcelain 2>/dev/null)" || refuse "cannot read the status of $WT."
[ -z "$st" ] || refuse "$WT has uncommitted changes. Unlike the pruner's REPORT, this
        path deletes, so there is no scaffolding allowance: any modification or
        untracked file refuses.
$(printf '%s\n' "$st" | sed 's/^/          /' | head -20)"

# --- G10: nothing unpushed ---------------------------------------------------

unpushed="$(git -C "$WT" rev-list --count HEAD --not --remotes 2>/dev/null)" \
  || refuse "cannot establish whether $WT has unpushed commits."
case "$unpushed" in
  ''|*[!0-9]*) refuse "cannot establish whether $WT has unpushed commits." ;;
esac
[ "$unpushed" -eq 0 ] || refuse "$WT has $unpushed commit(s) that no remote-tracking ref
        contains. Push them, or confirm by hand where they landed — a script must
        never decide that commits it cannot find anywhere are expendable."

# --- G11: every recorded PR is merged, by URL --------------------------------

PRS="$(fm_list_urls "$fm" pr)"
[ -n "$PRS" ] || refuse "$rel is done but records no PR URL in 'pr:'. Merged PRs are the
        evidence this removal rests on; without one there is nothing to check."

command -v gh >/dev/null 2>&1 || refuse "gh is not available, so the recorded PR(s) cannot
        be checked. An unknown must never be what authorises a deletion."

pr_count=0; own_repo=1
while IFS= read -r url; do
  [ -n "$url" ] || continue
  pr_count=$((pr_count + 1))
  # `<owner>/<repo>` out of a github PR URL, so a task whose only merged PR lives
  # in some other repo cannot clear this repo's worktree.
  slug="$(printf '%s' "$url" | sed -n 's#^https\{0,1\}://[^/]*/\([^/]*\)/\([^/]*\)/pull/[0-9]*.*#\1/\2#p')"
  [ "$slug" = "$REPO_REC" ] && own_repo=0
  state="$( gh pr view "$url" --json state --jq '.state' 2>/dev/null )" \
    || refuse "gh could not read $url (auth, network, or a deleted PR). Refusing
        rather than assuming it merged."
  case "$state" in
    MERGED) ;;
    OPEN|CLOSED|DRAFT) refuse "$url is $state, not MERGED. Every recorded PR must have
        merged — checked by URL, never by branch name, which is how a recycled
        name once carried an old merged PR onto a live worktree." ;;
    *) refuse "gh reported an unrecognised state '$state' for $url." ;;
  esac
done <<EOF
$PRS
EOF

[ "$own_repo" -eq 0 ] || refuse "none of the $pr_count recorded PR URL(s) belongs to
        $REPO_REC, so none of them is evidence about this repo's worktree."

# --- G12: liveness, last, because it is the one that clears with time --------
# RECURSIVE, deliberately: an agent editing `src/foo/bar.ts` never changes the
# mtime of the worktree root, so a root-only check ages a live agent out of the
# window while work is going on in it. Heavy caches are pruned so the walk stays
# cheap (39 ms on a 664 MB repo) — and note that pruning a directory means
# activity inside it does NOT protect the worktree, so this list stays short and
# holds only names that are unambiguously a cache or a generated store. `dist`,
# `build`, `target` and `vendor` are deliberately absent: they are tracked source
# in some repos.
LIVENESS_PRUNE=( node_modules .git '.pnpm-store*' '.bun-cache*' .venv venv
                 __pycache__ .pytest_cache .mypy_cache .next .nuxt .turbo
                 .cache .gradle )
recently_active() { # <worktree>
  local wt=$1 mins=${PRUNE_ACTIVE_MINUTES:-120} args=() n
  [[ "$mins" =~ ^[0-9]+$ ]] || mins=120
  [ "$mins" -gt 0 ] || return 1
  # The root's own mtime, checked separately so a worktree whose directory
  # happens to be NAMED like a cache is not pruned out of its own liveness test.
  if [ -n "$(find "$wt" -maxdepth 0 -mmin "-$mins" 2>/dev/null)" ]; then return 0; fi
  for n in "${LIVENESS_PRUNE[@]}"; do args+=( -name "$n" -o ); done
  args+=( -false )
  [ -n "$(find "$wt" -mindepth 1 \( "${args[@]}" \) -prune -o -mmin "-$mins" -print 2>/dev/null | head -1)" ]
}

if recently_active "$WT"; then
  refuse "$WT was touched within ${PRUNE_ACTIVE_MINUTES:-120} minute(s), so something may
        still be working in it. This one clears with time — ask again on a later
        tick. (A clean tree is not evidence of an idle worktree: an agent that
        has not written a file yet looks exactly like an abandoned checkout, and
        that is the window the 2026-08-04 dispatches were destroyed in.)"
fi

# --- remove ------------------------------------------------------------------

if [ "$DRY" -eq 1 ]; then
  printf 'would remove: %s  [%s]  (task %s, %d PR(s) merged)\n' "$WT" "$branch" "$rel" "$pr_count"
  exit 0
fi

# Deliberately WITHOUT `--force`: `git status --porcelain` does not see ignored
# files, so a worktree whose only remaining content is an ignored `.env` passes
# G9 — and `--force` would delete it. Plain `remove` refuses instead, and that
# refusal is reported as this script's refusal.
if ! out="$(git -C "$REPO_DIR" worktree remove "$WT" 2>&1)"; then
  refuse "git declined to remove $WT (no --force is ever passed, so an ignored
        file left in the tree is a human's decision):
$(printf '%s\n' "$out" | sed 's/^/          /')"
fi

# VERIFY THE WRITE. A false success is worse than the error it claims to fix: a
# report of "removed" for a directory still on disk sends the next tick past a
# worktree nobody will look at again.
still_registered=1
while IFS= read -r line; do
  case "$line" in
    "worktree "*) [ "${line#worktree }" = "$WT" ] && still_registered=0 ;;
  esac
done <<EOF
$(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null)
EOF

if [ -d "$WT" ] || [ "$still_registered" -eq 0 ]; then
  printf 'FAILED: git exited 0 but %s is still %s.\n' "$WT" \
    "$([ -d "$WT" ] && printf 'on disk' || printf 'registered')" >&2
  exit 1
fi

printf 'removed: %s  [%s]  (task %s, %d PR(s) merged)\n' "$WT" "$branch" "$rel" "$pr_count"
printf 'note: branch %s still exists — removal deletes the working directory and the\n' "$branch"
printf '      admin entry, never the branch or any commit.\n'
exit 0
