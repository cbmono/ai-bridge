#!/usr/bin/env bash
#
# resolve-max-agents.sh — print the concurrency cap this MACHINE should honour.
#
#   Usage: scripts/resolve-max-agents.sh [--instance DIR]
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE — the same reason resolve-model.sh does.
# `maxAgentsInFlight` lived only as prose in pm-loop.md and project-manager.md, so the cap
# was honoured wherever somebody remembered to read the file. Worse, it was TRACKED, which
# forces one number on every clone of a shared bundle.
#
# Measured 2026-08-29: the key read 4 / 6 / 10 across three instances on ONE 11-core Mac —
# up to 20 concurrent agents against a measured ceiling near 4. The cap is per instance and
# the CPU is per machine (SCHEMA.md records that hole), so the number is a statement about
# THIS machine's capacity, not about the group's policy. That makes it a per-machine key:
# two clones disagreeing about it breaks nothing, while one tracked number is wrong on
# every machine but the author's.
#
# RESOLUTION ORDER, and absence is never an error:
#   instance.config.local.json : maxAgentsInFlight   (this machine)
#   instance.config.json       : maxAgentsInFlight   (the tracked default)
#
# WHY IT INVENTS NO DEFAULT. Absent from both, this prints nothing and exits 1, exactly as
# resolve-model.sh does for an agent with no tier — the CALLER then applies the fallback
# its own document states. A default baked in here would be a third number competing with
# the ones already written down, and a resolver that guesses is worse than one that says it
# does not know. Same for a value that is not a positive integer: refused, not rounded.
set -uo pipefail

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top of
    # the loop with the same argv and spins forever (the bug resolve-model.sh hit).
    --instance)
      [ $# -ge 2 ] || { echo "resolve-max-agents: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    *) echo "resolve-max-agents: unexpected argument $1" >&2; exit 2 ;;
  esac
done

# Local override first, then the tracked file — the precedence every overridable key
# uses (SCHEMA.md, "Per-machine config overrides"), implemented ONCE in
# `scripts/resolve-config.sh` and delegated to here. The per-key merge lives there too, so
# a local file naming one key never blanks the rest of the config.
#
# THE SELF PATH IS RESOLVED THROUGH THE SYMLINK for the reason resolve-model.sh states: an
# instance stamped before that helper shipped has no copy in its own `scripts/`, and
# `dirname "$0"` would look exactly there.
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
resolver="$here/resolve-config.sh"
[ -n "$here" ] && [ -f "$resolver" ] || {
  echo "resolve-max-agents: scripts/resolve-config.sh not found beside this script" >&2; exit 2; }

# `--json`, NOT the plain value, and that is what preserves the type check. Plain mode
# prints a string bare, so `"maxAgentsInFlight": "4"` and `: 4` would arrive here identical
# and a quoted cap would start being accepted — a silent widening of a contract whose whole
# job is to refuse. json.dumps keeps the quotes, so `"4"` fails the digits-only match below
# exactly as Python's `isinstance(cap, int)` used to reject it.
cap="$(bash "$resolver" --instance "$inst" --json maxAgentsInFlight)" || exit 1

# REFUSED, NOT ROUNDED. Everything that is not an unquoted non-negative integer literal
# fails this match: `true` (the case worth naming — Python's `isinstance(True, int)` is
# True, so a boolean would otherwise have resolved to a cap of 1 and looked deliberate),
# `"4"`, `4.0`, `-1`, `null`, and a list or an object.
case "$cap" in
  ""|*[!0-9]*) exit 1 ;;
esac
[ "$cap" -ge 1 ] || exit 1
printf '%s\n' "$cap"
