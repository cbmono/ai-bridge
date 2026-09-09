#!/usr/bin/env bash
#
# scratch-path-is-ignored.test.sh — the scratch path CONVENTIONS.md names must RESOLVE to
# something git-ignored, and nothing tracked may live under it.
#
# Exit 0 pass · 1 fail · 2 setup · 3 a repo-redirecting GIT_* is set.
# Why: projects/launcher-verification-contract/task-015 (the rule named `.scratch/`, which
# this repo TRACKS, so an obedient agent's cleanup deleted a tracked file).
#
# THE PATH IS READ OUT OF THE RULE, never spelled here. A test pinning `.scratch` — or
# `tmp` — passes the day someone renames the directory and reopens the same hole.
#
# AND THE FIXTURE IS BUILT, never probed for. `.scratch/` looks ignored in this clone only
# because of `.git/info/exclude`, which is per-clone and never committed: probing the live
# checkout answers the opposite of what CI and every other clone see. So the fixture takes
# the .gitignore from HEAD — the only copy every clone has.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"

for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
         GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_CONFIG; do
  [ -z "${!v:-}" ] || { echo "scratch-path-is-ignored.test: $v is set — a fixture would commit into the repo under test. Unset it." >&2; exit 3; }
done
command -v git >/dev/null 2>&1 || { echo "scratch-path-is-ignored.test: git not on PATH" >&2; exit 2; }
[ -f "$CONV" ] || { echo "scratch-path-is-ignored.test: $CONV not found" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/scratch-path-is-ignored.XXXXXX")" || {
  echo "scratch-path-is-ignored.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# Every git call: no inherited repo, no user config, no hooks, identity per invocation.
g() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
      -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR -u GIT_NAMESPACE \
      -u GIT_CONFIG -u GIT_CONFIG_COUNT \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      git -c user.name=fixture -c user.email=fixture@example.invalid \
          -c commit.gpgsign=false -c core.hooksPath="$TMP/no-hooks" \
          -c init.defaultBranch=main -c advice.detachedHead=false "$@"
}

# =======================================================================================
echo "== 1. the path comes out of the rule, and there is exactly one of it =="
# =======================================================================================
extract() { # <conventions file> -> the path the scratch rule names, without <worktree>/
  # shellcheck disable=SC2016  # the backticks are markdown in the rule, not a substitution
  sed -n 's/^.*Scratch files go in `<worktree>\/\([^`]*\)`.*$/\1/p' "$1"
}
SCRATCH="$(extract "$CONV")"
ok "the scratch rule names exactly one path" \
   "$(printf '%s\n' "$SCRATCH" | grep -c . | tr -d ' ')" 1
[ -n "$SCRATCH" ] || { echo "scratch-path-is-ignored.test: no scratch path in $CONV" >&2; exit 2; }
P="${SCRATCH%/}"
printf '  ---   the rule names <worktree>/%s\n' "$SCRATCH"

# NON-VACUITY: the same extractor over a CONVENTIONS with the rule deleted finds nothing,
# so a green run cannot mean "the sed matched something that was never the rule".
grep -v 'Scratch files go in' "$CONV" > "$TMP/conv-no-rule.md"
ok "…and the extractor finds none with the rule deleted" \
   "$(extract "$TMP/conv-no-rule.md" | grep -c . | tr -d ' ')" 0

# =======================================================================================
echo "== 2. this repo tracks nothing under it — the half that is committed, not local =="
# =======================================================================================
TRACKED_HERE="$(g -C "$REPO" ls-files -- "$SCRATCH")"
ok "git ls-files finds no tracked file under $SCRATCH" \
   "$(printf '%s\n' "$TRACKED_HERE" | grep -c . | tr -d ' ')" 0

# =======================================================================================
echo "== 3. a fixture repo carrying this repo's COMMITTED .gitignore ignores it =="
# =======================================================================================
g -C "$REPO" show HEAD:.gitignore > "$TMP/gitignore-head" 2>/dev/null || {
  echo "scratch-path-is-ignored.test: no .gitignore at HEAD" >&2; exit 2; }

build() { # <dir> <gitignore source> [newline-separated tracked paths]
  local d="$1" ig="$2" tracked="${3:-}" f
  mkdir -p "$d" || return 1
  g init -q "$d" >/dev/null 2>&1 || return 1
  cp "$ig" "$d/.gitignore" || return 1
  printf 'kept\n' > "$d/keep.md"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$d/$(dirname "$f")" || return 1
    printf 'committed by accident\n' > "$d/$f" || return 1
  done <<<"$tracked"
  g -C "$d" add -A >/dev/null 2>&1 || return 1
  g -C "$d" commit -q -m fixture >/dev/null 2>&1 || return 1
}

ignored() { # <dir> -> yes|no
  g -C "$1" check-ignore -q -- "$P/probe.txt" && echo yes || echo no
}

# Does a scratch file show up as work while it sits there?
visible() { # <dir> -> yes|no
  local d="$1" st
  mkdir -p "$d/$P" || return 1
  printf 'draft\n' > "$d/$P/pr-body.md"
  st="$(g -C "$d" status --porcelain)"
  # Only what this probe made: an `rm -rf` here would inflict the very damage the next
  # probe exists to measure, and did — it made section 5 report `same`.
  rm -f "$d/$P/pr-body.md"
  rmdir "$d/$P" 2>/dev/null || true
  [ -n "$st" ] && echo yes || echo no
}

# The incident itself: write scratch, then run the cleanup an obedient agent runs.
# `ls-files` alone is the index and a deleted tracked file is still in it — the state of
# the tracked files on disk is what the cleanup damaged, so the fingerprint carries both.
tracked_state() { # <dir>
  g -C "$1" ls-files | sort
  g -C "$1" status --porcelain | sort
}
roundtrip() { # <dir> -> same|changed
  local d="$1" before after
  before="$(tracked_state "$d")"
  mkdir -p "$d/$P/sub" || return 1
  printf 'draft\n' > "$d/$P/pr-body.md"
  printf 'probe\n' > "$d/$P/sub/notes.txt"
  rm -rf "${d:?}/$P"
  after="$(tracked_state "$d")"
  [ "$before" = "$after" ] && echo same || echo changed
}

# The fixture mirrors this repo on BOTH axes — the committed ignore, and whatever this
# repo actually tracks under the named path — so section 4 measures the real incident.
FIX="$TMP/fixture"
ok "fixture repo built" \
   "$(build "$FIX" "$TMP/gitignore-head" "$TRACKED_HERE" && echo yes || echo no)" yes
ok "…and it ignores $SCRATCH"                  "$(ignored "$FIX")" yes
ok "…so a scratch file never reads as work"    "$(visible "$FIX")" no

# =======================================================================================
echo "== 4. write then delete leaves the tracked set untouched =="
# =======================================================================================
ok "an agent's scratch write + cleanup changes no tracked file" "$(roundtrip "$FIX")" same

# =======================================================================================
echo "== 5. the same three probes on the PRE-FIX repo answer the other way =="
# =======================================================================================
# A repo that does not ignore the named path and tracks a file under it — exactly the
# state this task fixed. Its .gitignore is EMPTY rather than edited, so nothing here
# depends on how the ignore happens to be spelled.
BAD="$TMP/fixture-unignored"
: > "$TMP/gitignore-empty"
ok "pre-fix fixture built" \
   "$(build "$BAD" "$TMP/gitignore-empty" "$P/m.txt" && echo yes || echo no)" yes
ok "…it does NOT ignore $SCRATCH"              "$(ignored "$BAD")" no
ok "…a scratch file there reads as work"       "$(visible "$BAD")" yes
ok "…and the cleanup deletes a tracked file"   "$(roundtrip "$BAD")" changed

# =======================================================================================
echo "== 6. no agent, skill or seed doc names a scratch path that disagrees =="
# =======================================================================================
TREES=("$REPO/plugin/agents" "$REPO/plugin/skills" "$REPO/plugin/seed")
NAMED="<worktree>/$SCRATCH"

# Every <worktree>/… path named on a line that is about scratch.
tokens="$(grep -rhi 'scratch' "${TREES[@]}" | grep -oE '<worktree>/[^`]+' | sort -u)"
ok "every <worktree>/… scratch path there is the one the rule names" "$tokens" "$NAMED"

# And any OTHER backticked token that names a scratch directory — `.scratch/`, a bare
# `.scratch`, a second `<worktree>/…scratch…` — is a disagreement whatever it is spelled.
# shellcheck disable=SC2016  # ditto: a markdown code span is what is being matched
strays="$(grep -rho '`[^`]*`' "${TREES[@]}" | tr -d '`' | grep -i 'scratch' \
          | grep -E '(/|^\.)' | grep -vFx "$NAMED" | sort -u)"
[ -z "$strays" ] || printf '%s\n' "$strays"
ok "no other scratch directory is named in agents/skills/seed" \
   "$([ -z "$strays" ] && echo none || echo some)" none

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
