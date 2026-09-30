# Sourced by a harness: PN (plugin), PMK (marketplace) and GH (owner/repo), read from the
# manifests directly — never from plugin/scripts/plugin-name.sh, whose answers the
# harnesses check. Not exported, so a script under test that failed to derive its own name
# cannot borrow this one. Unreadable manifests stop the harness: a blank name matches
# everything a grep asks about.
_pn_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_pn_name() { sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }
PN="$(_pn_name "$_pn_root/plugin/.claude-plugin/plugin.json")"
PMK="$(_pn_name "$_pn_root/.claude-plugin/marketplace.json")"
GH="$(sed -n 's#^  "repository": *"https://github.com/\([^"]*\)".*#\1#p' "$_pn_root/plugin/.claude-plugin/plugin.json" | head -1)"
[ -n "$PN" ] && [ -n "$PMK" ] && [ -n "$GH" ] \
  || { echo "tests/tools/plugin-name.sh: cannot read the plugin, marketplace or repo name" >&2; exit 2; }
unset _pn_root
