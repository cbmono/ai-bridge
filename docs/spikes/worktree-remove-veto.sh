#!/usr/bin/env bash
#
# worktree-remove-veto.sh — spike artifact for docs/spikes/native-worktrees.md.
# Decides whether a WorktreeRemove may delete <worktreeRoot>/<task-id>, reading the
# task document only: no network, no scan, no guess.
#   0 = remove may proceed (exactly one task doc, `pr:` empty, status terminal)
#   1 = KEEP the tree (anything else, including anything it could not establish)
# Usage: worktree-remove-veto.sh <worktree-path> [--bundle <dir>]   (dir: $CLAUDE_PROJECT_DIR)
# NOT WIRED as a hook: WorktreeRemove did not fire in any measured run, and its payload
# shape is therefore unmeasured — the path is taken from argv, not parsed out of stdin.
set -uo pipefail

keep() { printf 'keep: %s\n' "$1" >&2; exit 1; }

WT="${1:-}"; shift 2>/dev/null || true
BUNDLE="${CLAUDE_PROJECT_DIR:-}"
[ "${1:-}" = "--bundle" ] && BUNDLE="${2:-}"

[ -n "$WT" ] || keep "no worktree path given"
[ -n "$BUNDLE" ] && [ -d "$BUNDLE" ] || keep "no bundle directory to read the task from"

id="$(basename "$WT" | sed -n 's/^\(task-[0-9][0-9]*\).*/\1/p')"
[ -n "$id" ] || keep "$(basename "$WT") does not start with a task id"

set -- "$BUNDLE"/projects/*/tasks/"$id"-*.md
[ "$#" -eq 1 ] && [ -f "$1" ] || keep "$id matches $# task documents, not exactly one"
doc="$1"

fm="$(awk 'NR==1 && $0!="---" { exit } NR>1 && $0=="---" { exit } NR>1' "$doc")"
[ -n "$fm" ] || keep "$id has no frontmatter to read"

# `pr:` inline (`pr: [ a ]`) or as a block list, same shape-tolerance as reclaim-worktree.sh.
prs="$(printf '%s\n' "$fm" | awk '
    index($0, "pr:") == 1 { grab = 1; print; next }
    grab && /^[[:space:]]/ { print; next }
    grab && /^-/ { print; next }
    grab { grab = 0 }
  ' | grep -coE 'https?://[^][:space:],"'"'"']+')"
[ "$prs" -eq 0 ] || keep "$id records $prs PR URL(s) — the work is live"

status="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*"\{0,1\}\([a-z-]*\).*/\1/p' | head -1)"
case "$status" in
  done|cancelled) ;;
  *) keep "$id is '${status:-<none>}', not terminal" ;;
esac

printf 'remove: %s is %s with no PR URL\n' "$id" "$status" >&2
