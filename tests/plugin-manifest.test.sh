#!/usr/bin/env bash
#
# plugin-manifest.test.sh — the plugin packaging surface: both manifests, the skill
# files, and (when the CLI is present) `claude plugin validate --strict`.
#
# The failure this exists for: a manifest edit that parses as JSON but breaks install —
# a renamed field, a `source` path that resolves to nothing, a skill without the
# frontmatter the loader keys on. Each is pinned from both directions where a mutation
# is cheap to plant.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

PJ="$REPO/plugin/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"

echo "== the two manifests parse, and their required fields hold =="
ok "plugin.json parses"        "$(jq empty "$PJ" >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…name is ai-bridge"        "$(jq -r .name "$PJ")" "ai-bridge"
ok "…version is semver"        "$(jq -r .version "$PJ" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$')" 1
ok "marketplace.json parses"   "$(jq empty "$MJ" >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…names the owner"          "$(jq -r '.owner.name // empty' "$MJ" | grep -c .)" 1
ok "…lists the plugin"         "$(jq -r '.plugins[0].name' "$MJ")" "ai-bridge"

echo "== the marketplace source resolves to the plugin it names =="
SRC="$(jq -r '.plugins[0].source' "$MJ")"
ok "source is a same-repo relative path" "$(printf '%s' "$SRC" | grep -c '^\./')" 1
ok "…and it resolves to a plugin manifest" \
   "$([ -f "$REPO/${SRC#./}/.claude-plugin/plugin.json" ] && echo yes || echo no)" yes
ok "…whose name matches the entry" \
   "$(jq -r .name "$REPO/${SRC#./}/.claude-plugin/plugin.json")" "$(jq -r '.plugins[0].name' "$MJ")"
ok "…and whose versions agree" \
   "$([ "$(jq -r .version "$PJ")" = "$(jq -r '.plugins[0].version' "$MJ")" ] && echo yes || echo no)" yes

echo "== the deprecation stub — ai-bridge-v2, for ONE version =="
# The transition name shipped for eight slices, so a machine that installed it finds out
# by NAME rather than by a command that quietly stopped resolving. Three properties, and
# the third is the one that matters: the stub must ship no agents and no hooks, because a
# second copy of a PreToolUse enforcement hook fires in every session on the machine and a
# second agent set would shadow the real one.
STUB="$REPO/plugin-deprecated"
if [ -d "$STUB" ]; then
  ok "the marketplace still lists ai-bridge-v2" \
     "$(jq -r '[.plugins[].name] | index("ai-bridge-v2") | if . == null then "no" else "yes" end' "$MJ")" yes
  ok "…its description says it is deprecated" \
     "$(jq -r '.plugins[] | select(.name=="ai-bridge-v2") | .description' "$MJ" | grep -ci 'deprecated')" 1
  ok "…and names the plugin that replaces it" \
     "$(jq -r '.plugins[] | select(.name=="ai-bridge-v2") | .description' "$MJ" | grep -c 'ai-bridge@ai-bridge')" 1
  ok "…its source resolves to the stub manifest" \
     "$([ -f "$STUB/.claude-plugin/plugin.json" ] && echo yes || echo no)" yes
  ok "…which carries the old name" "$(jq -r .name "$STUB/.claude-plugin/plugin.json")" "ai-bridge-v2"
  ok "…ships no agents"            "$([ -e "$STUB/agents" ] && echo no || echo yes)" yes
  ok "…ships no hooks"             "$([ -e "$STUB/hooks" ] && echo no || echo yes)" yes
  ok "…and exactly one skill"      "$(ls -1 "$STUB/skills" 2>/dev/null | wc -l | tr -d ' ')" 1
else
  echo "  NOTE  plugin-deprecated/ is gone — the one-version stub has been removed."
fi

echo "== every skill has the frontmatter the loader keys on =="
n=0
for sk in "$REPO"/plugin/skills/*/SKILL.md; do
  [ -f "$sk" ] || continue
  n=$((n+1))
  base="$(basename "$(dirname "$sk")")"
  ok "$base: has a description" "$(awk '/^---$/{c++} c==1 && /^description:/{print "yes"; exit}' "$sk")" yes
done
ok "at least the two launch skills exist (scan not vacuous)" "$([ "$n" -ge 2 ] && echo yes || echo no)" yes

echo "== .claude-plugin/ holds ONLY its manifest (the documented layout rule) =="
ok "plugin/.claude-plugin has one entry" "$(ls -A "$REPO/plugin/.claude-plugin" | wc -l | tr -d ' ')" 1
ok "root .claude-plugin has one entry"   "$(ls -A "$REPO/.claude-plugin" | wc -l | tr -d ' ')" 1

echo "== the CLI's own validator, when present =="
if command -v claude >/dev/null 2>&1; then
  out="$(claude plugin validate "$REPO/plugin" --strict 2>&1)"; rc=$?
  ok "claude plugin validate --strict passes" "$rc" 0
  # On failure, the validator's own diagnostics are the finding — "got 1, want 0"
  # alone names no field.
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | sed 's/^/        | /'; fi
  if [ -d "$STUB" ]; then
    out="$(claude plugin validate "$STUB" --strict 2>&1)"; rc=$?
    ok "…and the deprecation stub validates too" "$rc" 0
    if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | sed 's/^/        | /'; fi
  fi
else
  echo "  SKIP  claude CLI not on PATH — jq checks above still hold"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
