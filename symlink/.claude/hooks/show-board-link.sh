#!/usr/bin/env bash
#
# show-board-link.sh — SessionStart hook (ai-bridge machinery).
#
# Prints the published board's URL when a session starts, so the human can open it
# immediately instead of hunting for it. Reads `boardArtifactUrl` — the SAME key /pm-loop
# reads to decide whether to render and publish the board each tick (see
# project-manager.md step 2c and pm-loop.md), so the URL has exactly one place it lives.
# This hook never writes it, and never invents one.
#
# LOCAL FILE FIRST, AND THAT IS A REVERSAL. This key used to be read from the tracked
# `instance.config.json` only, on the ground that one URL means one shared page. That
# reasoning assumed two clones could publish to one artifact, and they cannot: artifact
# publishing is ACCOUNT-SCOPED, so exactly one account can ever update a given URL and
# the second human's tick publishes nothing at all. So each human records THEIR OWN board
# in the gitignored `instance.config.local.json`, which wins here; the tracked file still
# answers on a single-human instance and for a clone that has set nothing. See SCHEMA.md
# → "Per-machine config overrides", which is the one place the overridable set is listed.
#
# Absence is the off switch, same shape as show-awaiting.sh. No `instance.config.json`
# (a non-bridge project that inherits this hook), no `.claude/agents` (same "is this
# actually an instance" signature check-machinery.sh and push-state.sh use), no
# `boardArtifactUrl` key in either file, or an empty/null value — every one of those
# means exit 0 in silence, never an error. Deliberately narrow: the ONLY thing this hook
# ever prints is the recorded URL. It reads no task document, so nothing task-derived can
# reach stdout — that's `show-awaiting.sh`'s job, already covered, and a second copy of
# its field discipline is exactly what this hook must not become.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cfg="$root/instance.config.json"
[ -f "$cfg" ] && [ -d "$root/.claude/agents" ] || exit 0

# A single top-level string field — grep/sed rather than a jq dependency, matching
# show-awaiting.sh and push-state.sh (bash + sed/awk only) rather than agent-control.sh's
# jq-hard-requirement, which pays for a real parser because it is a security control.
# Anchored on the exact key so the neighbouring `"$boardArtifactUrl"` doc string (one
# character different) can never match.
#
# `tr` FIRST, and it is load-bearing rather than tidying. The tracked config is pretty-
# printed one member per line, so a line-anchored pattern found the key there — but a
# LOCAL file is a one-liner (`{ "ownerGithubUser": "…" }` is the shape SCHEMA.md tells a
# second human to write), and against `{ "boardArtifactUrl": "…" }` that same pattern
# matches nothing at all: the key is not at the start of a line and the value is followed
# by ` }`. Breaking every `{` and `,` onto its own line puts each JSON member at a line
# start whichever way the file is formatted, and it keeps the anchor — which is the part
# that stops the `"$boardArtifactUrl"` doc string from being read as the URL.
#
# The local file is read FIRST and only a NON-EMPTY value there wins: a local file that
# does not mention the key — the common case, since it usually carries only
# `ownerGithubUser` — is not an override, and must not blank a URL the tracked file has.
url=""
for c in "$root/instance.config.local.json" "$cfg"; do
  [ -f "$c" ] || continue
  url="$(tr '{,' '\n\n' < "$c" \
    | sed -n 's/^[[:space:]]*"boardArtifactUrl"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*}\{0,1\}[[:space:]]*$/\1/p' \
    | head -n1)"
  [ -n "$url" ] && break
done

[ -n "$url" ] || exit 0

echo "🔗 Board: $url"
