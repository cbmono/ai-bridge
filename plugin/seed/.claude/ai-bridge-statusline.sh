#!/usr/bin/env bash
#
# ai-bridge-statusline.sh — the bundle's `statusLine` command. SEED content: yours once
# copied, and safe to delete (the key in .claude/settings.json goes with it).
#
# IT RESOLVES THE PLUGIN AT RUN TIME. A `statusLine` command gets no
# `${CLAUDE_PLUGIN_ROOT}` expansion, and a version-scoped cache path rots on every plugin
# update — so the newest installed copy is found here instead of baked into settings.json.
# Exit 0 always: a status line never fails a session.
set -uo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || exit 0
cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache"
line="$(ls -d "$cache"/*/ai-bridge/*/scripts/status-line.sh 2>/dev/null | sort -V | tail -n1)"
[ -n "$line" ] || exit 0
exec bash "$line" --instance "$here"
