#!/usr/bin/env bash
#
# show-board-link.sh — SessionStart hook (ai-bridge machinery).
#
# Prints the published board's URL when a session starts, so the human can open it
# immediately instead of hunting for it. Reads `boardArtifactUrl` from
# `instance.config.json` — the SAME key /pm-loop reads to decide whether to render and
# publish the board each tick (see project-manager.md step 2c and pm-loop.md), so the
# URL has exactly one place it lives. This hook never writes it, and never invents one.
#
# Absence is the off switch, same shape as show-awaiting.sh. No `instance.config.json`
# (a non-bridge project that inherits this hook), no `.claude/agents` (same "is this
# actually an instance" signature check-machinery.sh and push-state.sh use), no
# `boardArtifactUrl` key, or an empty/null value — every one of those means exit 0 in
# silence, never an error. Deliberately narrow: the ONLY thing this hook ever prints is
# the recorded URL. It reads no task document, so nothing task-derived can reach stdout —
# that's `show-awaiting.sh`'s job, already covered, and a second copy of its field
# discipline is exactly what this hook must not become.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cfg="$root/instance.config.json"
[ -f "$cfg" ] && [ -d "$root/.claude/agents" ] || exit 0

# A single top-level string field — grep/sed rather than a jq dependency, matching
# show-awaiting.sh and push-state.sh (bash + sed/awk only) rather than agent-control.sh's
# jq-hard-requirement, which pays for a real parser because it is a security control.
# Anchored on the exact key so the neighbouring `"$boardArtifactUrl"` doc string (one
# character different) can never match.
url="$(sed -n 's/^[[:space:]]*"boardArtifactUrl"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p' "$cfg" | head -n1)"

[ -n "$url" ] || exit 0

echo "🔗 Board: $url"
