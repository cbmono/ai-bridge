#!/usr/bin/env bash
#
# resolve-model.sh — print the model alias a given agent should run on.
#
#   Usage: scripts/resolve-model.sh <agent-name> [--instance DIR]
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE.
# `roleTiers`/`models` lived only as prose in SCHEMA.md, project-manager.md,
# advisor.md, audit.md and pm-loop.md — five files telling an agent to go and look
# something up, and NO code that read it. So the config governed exactly the dispatch
# paths whose markdown happened to mention it (the /pm-loop tick, the PM's own
# dispatches) and nothing else. Every ad-hoc `Agent` dispatch from a main session — a
# documented, legitimate mode — silently ignored it, because the Agent tool takes its
# model from its own parameter, else the agent's frontmatter, else the parent. Measured
# 2026-08-28: three separate sessions each reported, independently, that they had not
# consulted the file.
#
# A rule in prose is obeyed where somebody remembered to obey it. This makes it
# answerable by one command, so "what model should X run on" has a mechanical answer
# any caller can get without reading five documents.
#
# RESOLUTION ORDER, and absence is never an error:
#   roleTiers[<agent>]  ->  a tier name (light|standard|deep|apex)
#   models[<tier>]      ->  an alias (e.g. sonnet)
# An agent with no roleTiers entry, or a tier with no models entry, prints nothing and
# exits 1 — the caller then inherits the session model, which is the documented
# behaviour when the keys are absent. Never guess an alias.
#
# Both keys are read from `instance.config.local.json` FIRST and the tracked
# `instance.config.json` second, per entry. THAT RULE IS NOT WRITTEN HERE: it lives in
# `scripts/resolve-config.sh`, which this delegates to, because the session banner needs
# the same precedence plus the answer to "which file won" and a second copy of the merge
# is how the two would come to disagree. This file owns the two-step lookup below and the
# contract that absence is not an error; precedence is that file's.
set -uo pipefail

agent=""; inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top
    # of the loop with the same argv and spins forever — verified by running it.
    --instance)
      [ $# -ge 2 ] || { echo "resolve-model: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    -*) echo "resolve-model: unknown flag $1" >&2; exit 2 ;;
    *) agent="$1"; shift ;;
  esac
done
[ -n "$agent" ] || { echo "Usage: resolve-model.sh <agent-name> [--instance DIR]" >&2; exit 2; }

# THE SELF PATH IS RESOLVED THROUGH THE SYMLINK, and that is load-bearing rather than
# tidy. `install.sh` links every machinery file individually into an instance, so an
# instance stamped BEFORE `resolve-config.sh` shipped has no such file in its own
# `scripts/` — a plain `dirname "$0"` would look there, miss it, and break a resolver that
# worked yesterday. `readlink` lands in the template that is actually executing, where the
# helper is guaranteed to sit beside this file. (The same idiom check-machinery.sh uses to
# name the template's current location.)
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
resolver="$here/resolve-config.sh"
[ -n "$here" ] && [ -f "$resolver" ] || {
  echo "resolve-model: scripts/resolve-config.sh not found beside this script" >&2; exit 2; }

# roleTiers[<agent>] -> a tier name, then models[<tier>] -> an alias. Either step missing
# means this prints nothing and exits 1: the caller then inherits the session model, which
# is the documented behaviour when the keys are absent. Never guess an alias.
tier="$(bash "$resolver" --instance "$inst" roleTiers "$agent")" || exit 1
[ -n "$tier" ] || exit 1
alias_name="$(bash "$resolver" --instance "$inst" models "$tier")" || exit 1
[ -n "$alias_name" ] || exit 1
printf '%s\n' "$alias_name"
