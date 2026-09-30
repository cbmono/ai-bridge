#!/usr/bin/env bash
#
# plugin-name.sh — this plugin's own name and marketplace, derived and never spelled.
#
#   . "$(dirname "$0")/plugin-name.sh"   sourced: sets AB_PLUGIN and AB_MARKETPLACE
#   plugin-name.sh [<plugin-root>]       prints AB_PLUGIN=… and AB_MARKETPLACE=…
#
# An install is <…>/plugins/cache/<marketplace>/<plugin>/<version>; a checkout reads the
# two manifests. Exit: 0, or 1 when no name can be derived. Reasoning: loopd/task-007.

ab_plugin_name() { # [<plugin-root>] -> sets AB_PLUGIN AB_MARKETPLACE
  local root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}" p mk ca
  root="${root%/}"; p="${root%/*}"; mk="${p%/*}"; ca="${mk%/*}"
  AB_PLUGIN="" AB_MARKETPLACE=""
  if [ "${ca##*/}" = cache ] && [ "$(basename "${ca%/*}")" = plugins ]; then
    AB_PLUGIN="${p##*/}" AB_MARKETPLACE="${mk##*/}"
  fi
  # The top-level "name" is the first one in either manifest; nested ones are indented further.
  [ -n "$AB_PLUGIN" ] || AB_PLUGIN="$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  [ -n "$AB_MARKETPLACE" ] || AB_MARKETPLACE="$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$root/../.claude-plugin/marketplace.json" 2>/dev/null | head -1)"
  [ -n "$AB_MARKETPLACE" ] || AB_MARKETPLACE="$AB_PLUGIN"
  export AB_PLUGIN AB_MARKETPLACE
  [ -n "$AB_PLUGIN" ]
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  ab_plugin_name "${1:-}" || { echo "plugin-name: cannot derive a name from ${1:-this plugin}" >&2; exit 1; }
  printf 'AB_PLUGIN=%s\nAB_MARKETPLACE=%s\n' "$AB_PLUGIN" "$AB_MARKETPLACE"
else
  ab_plugin_name || true
fi
