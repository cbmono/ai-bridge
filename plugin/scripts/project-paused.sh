#!/usr/bin/env bash
#
# project-paused.sh — is the project that owns <path> paused? The ONE reader of pause state.
#
#   Usage: project-paused.sh <path>    # a task (or project.md) under projects/<slug>/, from the instance root
#
# Exit: 0 not paused · 1 paused, the ONLY skip · 2 cannot answer (usage, not an instance root,
# no SCHEMA.md, absent or unreadable project.md) — task-owner.sh's contract. A pause gates
# DISPATCH only: callers stop offering `ready` work and non-`merge` AWAITING rows, and no
# task file is ever rewritten. Verified by tests/project-paused.test.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

refuse() { echo "error: $1" >&2; exit 2; }

[ "$#" -eq 1 ] && [ -n "$1" ] && [ "${1#-}" = "$1" ] || refuse "usage: $(basename "$0") <path>"
ab_is_bundle . || refuse "run from a control-panel instance root (instance.config.json)."
[ -f "$AB_SCHEMA" ] || refuse "no $AB_SCHEMA — not a stamped instance."

# Canonicalised both sides, as task-owner.sh does: macOS /var is a link to /private/var.
tdir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || refuse "no such path: $1"
rel="$tdir/$(basename "$1")"; rel="${rel#"$(pwd -P)"/}"
slug="$(printf '%s\n' "$rel" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"
[ -n "$slug" ] || refuse "$1 is not under projects/<slug>/."
pm="projects/$slug/project.md"
[ -f "$pm" ] && [ -r "$pm" ] || refuse "cannot read $pm."

# First `status:` inside a CLOSED frontmatter block; an unterminated block is unreadable.
st="$(awk '
  NR==1 && $0!="---" { exit 3 }
  /^---$/ { if (++n==2) { closed=1; exit } ; next }
  n==1 && !got && /^status:/ {
    v=$0; sub(/^status:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
    gsub(/["\047]/, "", v); sub(/[[:space:]]+$/, "", v); got=1
  }
  END { if (!closed) exit 4; print v }
' "$pm")" || refuse "$pm has no readable frontmatter."

if [ "$st" = paused ]; then
  echo "paused: $pm — dispatch nothing new from it."
  exit 1
fi
echo "ok: $pm is ${st:-unset}, not paused."
