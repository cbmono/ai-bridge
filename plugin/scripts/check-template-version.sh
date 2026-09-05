#!/usr/bin/env bash
#
# check-template-version.sh — is the template this instance links BEHIND the remote?
#
# One question, one answer, and the answer is usually silence. It compares the `VERSION`
# file in the template checkout the instance's symlinks point into against the same file
# on the remote's default branch, and prints a line ONLY when the remote is newer.
#
# WHY A VERSION COMPARISON AND NOT A COMMIT COUNT. An instance consumes the template
# through per-file symlinks, so most changes are live the moment they are merged and a
# "you are N commits behind" line would fire constantly for changes that already reached
# here. The two that do NOT arrive by themselves are the ones worth a line: a NEW file
# in the plugin reaches a machine only when the plugin is UPDATED, and `seed/` content is
# copied into a bundle once, ever. Both are exactly the changes the bump convention
# (`docs/conventions.md` §20) requires a version bump for, so the version — not the commit
# graph — is the signal.
#
# IT SPEAKS ONLY WHEN BEHIND. Equal or ahead is byte-empty output. A line every session is
# wallpaper, and wallpaper is how AWAITING.md rows come to be skipped; the banner this
# feeds has the same rule for every one of its sections.
#
# AND A FAILURE IS NEVER "BEHIND". Unreachable, unauthenticated, offline, no git, not a
# checkout, no remote-tracking ref, no VERSION on either side, a version this cannot parse
# — every one of those exits 0 with nothing printed. A false "you are behind" trains the
# human to ignore the true one, and absence is never an error anywhere else in this
# machinery. It is also why `--fetch` is OPT-IN: on the session path there is no network
# call at all, so there is no failure to misread and no banner blocked on a socket. Without
# it the comparison reads the remote-tracking ref already on disk, which can only ever
# under-report.
#
# WHAT IT CANNOT SEE, stated because a checker that overclaims is worse than none: a
# template checkout parked on an old commit or a stale branch whose VERSION happens to
# equal the remote's is INVISIBLE here. The version moves when the bump convention says it
# moves, so this detects drift across a bump and nothing finer.
#
# NEVER WRITES, NEVER FETCHES UNLESS ASKED, NEVER REPAIRS. It reports; the human pulls and
# re-stamps. Exit status is 0 on every path, including "behind": the caller is a
# SessionStart banner, and a non-zero exit there is a failed hook, not a message.
#
#   check-template-version.sh [--template <dir>] [--instance <dir>] [--ref <ref>] [--fetch]
#
# Verified by tests/template-version.test.sh.
set -uo pipefail

TEMPLATE=""; INSTANCE=""; REF=""; FETCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --template)   shift; TEMPLATE="${1:-}"; shift || true ;;
    --template=*) TEMPLATE="${1#--template=}"; shift ;;
    --instance)   shift; INSTANCE="${1:-}"; shift || true ;;
    --instance=*) INSTANCE="${1#--instance=}"; shift ;;
    --ref)        shift; REF="${1:-}"; shift || true ;;
    --ref=*)      REF="${1#--ref=}"; shift ;;
    --fetch)      FETCH=1; shift ;;
    # An unknown argument is IGNORED rather than fatal, for the same reason the banner
    # ignores one: this runs at session start, and refusing to start over a flag a future
    # settings.json passed is a worse outcome than not understanding it.
    *) shift ;;
  esac
done

[ -n "$INSTANCE" ] || INSTANCE="${CLAUDE_PROJECT_DIR:-$PWD}"

# WHERE THE TEMPLATE IS, read from this script's own path when it was not passed one. The
# instance's copy of this file IS a symlink into the template, so resolving it is the one
# lookup that cannot be wrong, because it is executing. Callers that already
# know (the banner, the tests) pass `--template` and skip this.
if [ -z "$TEMPLATE" ]; then
  self="${BASH_SOURCE[0]:-$0}"
  # ABSOLUTE BEFORE ANYTHING ELSE: a relative invocation would make the walk below start
  # from a path that means nothing outside this process's cwd, and a symlink is allowed to
  # hold a relative target that only means anything beside the link itself.
  case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
  if [ -L "$self" ]; then
    target="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
    case "$target" in /*) self="$target" ;; *) self="$(dirname "$self")/$target" ;; esac
  fi
  # The layout is fixed by the marketplace manifest (`source: ./plugin`): this file sits at
  # <root>/plugin/scripts/, so the template root is exactly two directories up. Derived and
  # then VERIFIED against `VERSION`, never searched for — a walk that keeps climbing finds
  # SOME ancestor with a VERSION file eventually, and comparing against an unrelated repo
  # is the one answer worse than silence.
  guess="$(cd "$(dirname "$self")/../.." 2>/dev/null && pwd || true)"
  [ -n "$guess" ] && [ -f "$guess/VERSION" ] && TEMPLATE="$guess"
fi
[ -n "$TEMPLATE" ] && [ -d "$TEMPLATE" ] || exit 0

# ---------------------------------------------------------------------------------------
# READING A VERSION — strict, because the two values are compared AND printed.
# ---------------------------------------------------------------------------------------
# STRICTER THAN THE BANNER'S DISPLAY FILTER, on purpose. The banner may print `9.9.9-rc1`;
# there is no defensible ordering between a pre-release and a release, so anything that is
# not a plain dotted run of digits is unparseable HERE and unparseable means silence. The
# same filter also settles the injection question for free: a value that reaches stdout is
# digits and dots, so a VERSION file carrying an ESC sequence cannot repaint a terminal.
# Fields are capped at 9 digits so the numeric compare below cannot overflow.
read_version() { # <raw file contents> ; prints a normalised version, or nothing
  local v
  v="$(printf '%s\n' "$1" | sed -n '1p' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$v" in
    ''|.*|*.|*..*) return 0 ;;
    *[!0-9.]*)     return 0 ;;
  esac
  [ "${#v}" -le 32 ] || return 0
  local IFS=. f
  for f in $v; do [ "${#f}" -le 9 ] || return 0; done
  printf '%s' "$v"
}

# newer <a> <b> — true when version <a> is strictly greater than version <b>. Field by
# field, numerically: `0.10.0` is newer than `0.9.1` and a string compare says the
# opposite, which is the single most likely way this check could lie. A missing field is 0,
# so `1.0` and `1.0.0` are equal. `10#` forces base 10 — `08` is an invalid octal literal
# and would otherwise abort the comparison mid-way.
newer() { # <a> <b>
  local IFS=. i n x y
  # shellcheck disable=SC2206  # the split on IFS IS the parse
  local -a A=($1) B=($2)
  n=${#A[@]}; [ "${#B[@]}" -gt "$n" ] && n=${#B[@]}
  for (( i = 0; i < n; i++ )); do
    x=$(( 10#${A[i]:-0} )); y=$(( 10#${B[i]:-0} ))
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 1
}

# ---------------------------------------------------------------------------------------
# THE TWO SIDES.
# ---------------------------------------------------------------------------------------
# HERE is the WORKING TREE, not HEAD: the working tree is what the instance's symlinks
# actually resolve into and what the banner prints, so it is what "this instance links"
# means. A checkout with an uncommitted VERSION is answered about as it is on disk.
here="$(read_version "$(cat -- "$TEMPLATE/VERSION" 2>/dev/null || true)")"
[ -n "$here" ] || exit 0

command -v git >/dev/null 2>&1 || exit 0
git -C "$TEMPLATE" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# THE ONLY NETWORK CALL IN THE FILE, and it is opt-in. A failed fetch ends the run in
# silence rather than falling through to the on-disk ref: the caller asked for a fresh
# answer, could not have one, and inventing a verdict out of stale data is the shape of
# false alarm this whole file is written to avoid.
# `GIT_TERMINAL_PROMPT=0` because the failure to survive here is not an error, it is a
# HANG: a remote whose credentials expired asks for a username on the terminal, and a check
# that stops a human's shell to ask them to log in is worse than the silence it was written
# to prefer. With the prompt off, that case fails immediately and exits like every other
# unreachable remote.
if [ "$FETCH" -eq 1 ]; then
  GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" fetch --quiet origin >/dev/null 2>&1 || exit 0
fi

# NEVER ASSUME `main` — NOT EVEN AS A FALLBACK. `origin/HEAD` is what the remote itself
# says its default branch is, and it is the only source consulted here. The previous
# fallback to the literal `origin/main` was defended as "a wrong name resolves to nothing
# and is therefore silent", which is true only on a remote that has no `main` at all: a
# template on a `master`, `next` or `trunk` remote that ALSO carries a stale `main` would
# have been compared against a branch this file invented, reporting an update that does not
# exist or missing one that does. A hardcoded branch name in the one script whose whole job
# is detecting drift is the sharpest available version of that mistake, and it contradicts
# the standing rule every other script here follows.
#
# UNRESOLVABLE ⇒ SILENCE, like every other thing this file cannot know. `--ref` stays the
# way a caller that DOES know which branch to compare says so.
if [ -z "$REF" ]; then
  REF="$(git -C "$TEMPLATE" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$REF" ] || exit 0
fi

remote_raw="$(git -C "$TEMPLATE" show "$REF:VERSION" 2>/dev/null)" || exit 0
there="$(read_version "$remote_raw")"
[ -n "$there" ] || exit 0

newer "$there" "$here" || exit 0

# ---------------------------------------------------------------------------------------
# THE LINE. Reached only when the remote is strictly newer.
# ---------------------------------------------------------------------------------------
# PLAIN TEXT, NO COLOUR. The caller that prints this is the session banner, whose stdout is
# a pipe into Claude Code rather than a terminal; escape codes on that path land in the
# transcript as literal bytes. The banner owns presentation, this file owns the verdict.
#
# THE REPAIR IS TWO COMMANDS AND THE SECOND ONE IS THE POINT: pulling the template updates
# every file already linked, but a file that is NEW in that pull reaches this instance only
# when the bundle is re-stamped. Someone who updates and stops is exactly the state this check
# exists to end.
# THE NAME IS DERIVED, NEVER A LITERAL. This file is symlinked into instances from a
# template checkout that is not required to be called anything in particular, and
# `plugin/**` carries no org, repo or path literals (`.claude/rules/machinery.md`). The
# checkout's own directory name is the honest label — it is also the name in the `git -C`
# line below, so a fork or a renamed clone names itself instead of claiming to be some
# other project. Control characters are stripped because the value comes from the
# filesystem and this string is printed; an unnameable path drops the parenthetical rather
# than printing an empty one.
name="$(basename -- "$TEMPLATE" 2>/dev/null | tr -d '[:cntrl:]')"
label="TEMPLATE UPDATE"
[ -n "$name" ] && label="TEMPLATE UPDATE ($name)"
printf '%s\n' "⬆️  $label — this machine runs ${here}, ${REF} has ${there}"
echo "    Update the plugin, then re-stamp this bundle (a seed change reaches a bundle"
echo "    only through a stamp, and only that way):"
echo "        /plugin update ai-bridge@ai-bridge      (then restart Claude Code)"
printf '        /ai-bridge:init %q\n' "$INSTANCE"
exit 0
