#!/usr/bin/env bash
#
# plugin-name.sh — this plugin's own name and marketplace, derived and never spelled.
#
#   . "$(dirname "$0")/plugin-name.sh"   sourced: sets PLUGIN_NAME and PLUGIN_MARKETPLACE
#   plugin-name.sh [<plugin-root>]       prints PLUGIN_NAME=… and PLUGIN_MARKETPLACE=…
#
# An install is <…>/plugins/cache/<marketplace>/<plugin>/<version>; a checkout reads the
# two manifests. Exit: 0, or 1 when no name can be derived. Reasoning: loopd/task-007.

ab_plugin_name() { # [<plugin-root>] -> sets PLUGIN_NAME PLUGIN_MARKETPLACE
  local root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}" p mk ca
  root="${root%/}"; p="${root%/*}"; mk="${p%/*}"; ca="${mk%/*}"
  PLUGIN_NAME="" PLUGIN_MARKETPLACE=""
  if [ "${ca##*/}" = cache ] && [ "$(basename "${ca%/*}")" = plugins ]; then
    PLUGIN_NAME="${p##*/}" PLUGIN_MARKETPLACE="${mk##*/}"
  fi
  # The top-level "name" is the first one in either manifest; nested ones are indented further.
  [ -n "$PLUGIN_NAME" ] || PLUGIN_NAME="$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  [ -n "$PLUGIN_MARKETPLACE" ] || PLUGIN_MARKETPLACE="$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$root/../.claude-plugin/marketplace.json" 2>/dev/null | head -1)"
  [ -n "$PLUGIN_MARKETPLACE" ] || PLUGIN_MARKETPLACE="$PLUGIN_NAME"
  export PLUGIN_NAME PLUGIN_MARKETPLACE
  [ -n "$PLUGIN_NAME" ]
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  ab_plugin_name "${1:-}" || { echo "plugin-name: cannot derive a name from ${1:-this plugin}" >&2; exit 1; }
  printf 'PLUGIN_NAME=%s\nPLUGIN_MARKETPLACE=%s\n' "$PLUGIN_NAME" "$PLUGIN_MARKETPLACE"
else
  ab_plugin_name || true
fi
