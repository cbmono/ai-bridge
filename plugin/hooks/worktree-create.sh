#!/usr/bin/env bash
#
# worktree-create.sh — WorktreeCreate hook. Places <worktreeRoot>/<task-id> of the
# task's `target_repo` on the task's `branch:` and prints it, so a session started as
# `claude --worktree <task-id>` lands in the tree the task already names.
#
#   stdout   the absolute path (the only thing the harness reads)
#   exit 0   printed it, OR `name` is not a task id — nothing printed, harness decides
#   exit 1   `name` IS a task id and this could not place it: creation ABORTS
#
# Contract measured in docs/spikes/native-worktrees.md (Claude Code 2.1.270).
set -uo pipefail

abort() { printf 'worktree-create: %s\n' "$1" >&2; exit 1; }

payload="$(cat)"
name="$(printf '%s' "$payload" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
id="$(printf '%s' "$name" | sed -n 's/^\(task-[0-9][0-9]*\).*/\1/p')"

# Not a task id ⇒ an in-session subagent (`agent-<opaque-id>`) or a human's own name.
# The payload cannot say which task those serve, so this hook never guesses at one.
[ -n "$id" ] || exit 0

BUNDLE="${CLAUDE_PROJECT_DIR:-}"
[ -n "$BUNDLE" ] || BUNDLE="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$BUNDLE" ] && [ -f "$BUNDLE/instance.config.json" ] || abort "no instance root to read $id from"

set -- "$BUNDLE"/projects/*/tasks/"$id"-*.md
[ "$#" -eq 1 ] && [ -f "$1" ] || abort "$id matches $# task documents, not exactly one"
DOC="$1"

fm="$(awk 'NR==1 && $0!="---" { exit } NR>1 && $0=="---" { exit } NR>1' "$DOC")"
[ -n "$fm" ] || abort "$id has no frontmatter"
field() { printf '%s\n' "$fm" | sed -n "s/^$1:[[:space:]]*//p" | head -1 | sed 's/^"//; s/"$//; s/[[:space:]]*$//'; }

TARGET="$(field target_repo)"
BRANCH="$(field branch)"; [ -n "$BRANCH" ] || BRANCH="$id"
[ -n "$TARGET" ] || abort "$id records no target_repo"

HERE="$(cd "$(dirname "$0")" && pwd)"
cfg() { # <key> — the two-file precedence, delegated; grep is the no-python3 fallback.
  local f v
  v="$(bash "$HERE/../scripts/resolve-config.sh" --instance "$BUNDLE" "$1" 2>/dev/null)" && [ -n "$v" ] && {
    printf '%s' "${v/#\~/$HOME}"; return 0; }
  for f in "$BUNDLE/instance.config.local.json" "$BUNDLE/instance.config.json"; do
    [ -f "$f" ] || continue
    v="$(grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$f" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
    [ -n "$v" ] && { printf '%s' "${v/#\~/$HOME}"; return 0; }
  done
  printf ''
}

REPOS_ROOT="$(cfg reposRoot)"
[ -n "$REPOS_ROOT" ] && [ -d "$REPOS_ROOT" ] || abort "reposRoot ('$REPOS_ROOT') is not a directory"
WT_ROOT="$(cfg worktreeRoot)"; [ -n "$WT_ROOT" ] || WT_ROOT="$REPOS_ROOT/_wt"

REPO="$REPOS_ROOT/${TARGET##*/}"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || abort "$TARGET is not cloned at $REPO"

# The task may already name the tree (the PM writes `worktree:` before dispatch). Honour
# it only inside a configured root: the document is text several agents edit.
WT="$(field worktree)"; [ -n "$WT" ] || WT="$WT_ROOT/$id"
case "$WT" in
  /*) ;; *) abort "$id records a relative worktree: '$WT'" ;;
esac
case "$WT" in
  *..*) abort "$id records a worktree containing '..'" ;;
  "$WT_ROOT"/*|"$REPOS_ROOT"/_wt/*) ;;
  *) abort "$id records a worktree outside $WT_ROOT: '$WT'" ;;
esac

if [ ! -d "$WT" ]; then
  mkdir -p "$(dirname "$WT")" || abort "cannot create $(dirname "$WT")"
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO" worktree add -q "$WT" "$BRANCH" 2>/dev/null || abort "worktree add on existing branch $BRANCH failed"
  else
    def="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"
    [ -n "$def" ] || abort "cannot detect the default branch of $REPO"
    git -C "$REPO" worktree add -q "$WT" -b "$BRANCH" "origin/$def" 2>/dev/null || abort "worktree add -b $BRANCH from origin/$def failed"
  fi
fi

# Existence is what the harness validates, and a non-existent path aborts creation there
# with a less useful message than this one.
[ -d "$WT" ] || abort "$WT does not exist after worktree add"
printf '%s\n' "$WT"
