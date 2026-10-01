#!/usr/bin/env bash
#
# plugin-name.test.sh — plugin/scripts/plugin-name.sh derives the plugin and marketplace
# name: from the install path's <cache>/<marketplace>/<plugin>/<version> shape, else from
# the two manifests. And a core installed under ANOTHER name still finds its companion,
# because resolve-autonomy.sh fails closed (every project `gated`) when it does not.
# Reasoning: loopd/task-007. Each derivation is also run on a mutant that must go red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
PNS="$REPO/plugin/scripts/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/plugin-name.XXXXXX")" || { echo "plugin-name.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
names() { bash "$1" ${2:+"$2"} 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }

echo "== 1. a checkout reads the two manifests =="
ok "the checkout names itself from the manifests" "$(names "$PNS")" "PLUGIN_NAME=$PN PLUGIN_MARKETPLACE=$PMK"
ok "…the same answer when sourced, with nothing printed" \
   "$(bash -c '. "$1" >"$2/src.out"; printf "%s@%s" "$PLUGIN_NAME" "$PLUGIN_MARKETPLACE"' _ "$PNS" "$TMP"):$(wc -c <"$TMP/src.out" | tr -d ' ')" "$PN@$PMK:0"
ok "…and through bundle-paths.sh, which every layout reader sources" \
   "$(bash -c '. "$1/bundle-paths.sh"; printf "%s@%s" "$PLUGIN_NAME" "$PLUGIN_MARKETPLACE"' _ "$REPO/plugin/scripts")" "$PN@$PMK"

echo
echo "== 2. an install is named by its path, not by its manifest =="
INST="$TMP/cfg/plugins/cache/loopd/loopd/3.0.0"
mkdir -p "$INST" && cp -R "$REPO/plugin/." "$INST/"
ok "the fixture really is an install: no marketplace manifest beside it" \
   "$([ -e "$INST/../.claude-plugin/marketplace.json" ] && echo present || echo absent)" absent
ok "…and its own manifest still says $PN" "$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$INST/.claude-plugin/plugin.json")" "$PN"
ok "the install path wins" "$(names "$INST/scripts/plugin-name.sh")" "PLUGIN_NAME=loopd PLUGIN_MARKETPLACE=loopd"
ok "…the plugin and marketplace segments are not swapped" \
   "$(names "$PNS" "$TMP/x/plugins/cache/mkt-a/plug-b/1.0.0/")" "PLUGIN_NAME=plug-b PLUGIN_MARKETPLACE=mkt-a"
ok "a path merely NAMED cache is not an install" \
   "$(names "$PNS" "$TMP/x/notplugins/cache/mkt-a/plug-b/1.0.0")" ""
ok "…nor is one with nothing readable, which exits 1" \
   "$(bash "$PNS" "$TMP/nowhere" >/dev/null 2>&1; echo $?)" 1

echo
echo "== 3. a core renamed to loopd still finds its yolo companion =="
YOLO="$TMP/cfg/plugins/cache/loopd/loopd-yolo/3.0.0"
mkdir -p "$YOLO/companion" && printf '# fixture\n' > "$YOLO/companion/AUTONOMY.md"
mkdir -p "$TMP/bundle"
write_registry() { # <core-key> <yolo-key>
  cat > "$TMP/cfg/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "$1": [
      { "scope": "user", "installPath": "$INST", "version": "3.0.0" }
    ],
    "$2": [
      { "scope": "user", "installPath": "$YOLO", "version": "3.0.0" }
    ]
  }
}
JSON
}
autonomy() { CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$INST/scripts/resolve-autonomy.sh" --bundle "$TMP/bundle" 2>/dev/null; echo "rc=$?"; }
write_registry "loopd@loopd" "loopd-yolo@loopd"
ok "the companion resolves under the renamed marketplace" "$(autonomy | tr '\n' ' ')" "$YOLO/companion/AUTONOMY.md rc=0 "
write_registry "loopd@loopd" "loopd-yolo@ai-bridge"
ok "…and one from another marketplace is still refused" "$(autonomy)" "rc=1"
write_registry "loopd@loopd" "ai-bridge-yolo@ai-bridge"
ok "…and so is the pre-rename id, ai-bridge-yolo@ai-bridge: gated" "$(autonomy)" "rc=1"
printf '{\n  "version": 2,\n  "plugins": {\n    "loopd-yolo@loopd": [\n      { "installPath": "%s" }\n    ]\n  }\n}\n' \
  "$YOLO" > "$TMP/cfg/plugins/installed_plugins.json"
ok "no core entry: the default marketplace is the path's, so it still resolves" \
   "$(autonomy | tr '\n' ' ')" "$YOLO/companion/AUTONOMY.md rc=0 "

echo
echo "== 4. mutants go RED =="
M="$TMP/mutant/plugins/cache/loopd/loopd/3.0.0"
mkdir -p "$M" && cp -R "$REPO/plugin/." "$M/"
sed 's/= cache \]/= nocache ]/' "$PNS" > "$M/scripts/plugin-name.sh"
ok "mutant A: without the path shape, an install reports its manifest" \
   "$(names "$M/scripts/plugin-name.sh")" "PLUGIN_NAME=$PN PLUGIN_MARKETPLACE=$PN"
sed 's/PLUGIN_NAME="${p##\*\/}" PLUGIN_MARKETPLACE="${mk##\*\/}"/PLUGIN_NAME="${mk##*\/}" PLUGIN_MARKETPLACE="${p##*\/}"/' "$PNS" > "$TMP/swapped.sh"
ok "mutant B: swapped segments are caught" \
   "$(names "$TMP/swapped.sh" "$TMP/x/plugins/cache/mkt-a/plug-b/1.0.0")" "PLUGIN_NAME=mkt-a PLUGIN_MARKETPLACE=plug-b"

sed 's/^DEFAULT_MARKETPLACE=.*/DEFAULT_MARKETPLACE="ai-bridge"/' "$REPO/plugin/scripts/resolve-autonomy.sh" > "$INST/scripts/resolve-autonomy.sh"
ok "mutant C: a hardcoded default turns the renamed install gated" "$(autonomy)" "rc=1"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
