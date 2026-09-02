#!/usr/bin/env bash
#
# plugin-agents.test.sh — the eight role agents ship in the plugin, and the plugin is
# now the ONLY place they ship from.
#
# WHAT THIS FILE USED TO BE, and why it is smaller: agent precedence is the REVERSE of
# skills — a same-named project agent SHADOWS the plugin copy (plugins are the lowest
# scope) — so the migration ran in two phases. Phase 1 shipped the agents here while the
# instance links remained (instances won, zero behaviour change), and this harness pinned
# BYTE-PARITY between the two copies, because two copies that cannot drift are one copy.
# Phase 2 landed with the name swap: symlink/.claude/agents/ is retired, the parity
# section is gone with the second copy it compared, and what is left are SHAPE checks on
# the plugin copies.
#
# The frontmatter section pins the facts the migration was planned around: every agent
# carries an explicit `name:` and an explicit `tools:` allowlist, and none uses a field
# plugins cannot ship (hooks, mcpServers, permissionMode) — a field added later would
# vanish silently at load. What it does NOT pin any more is bare-name dispatch: measured
# on 2026-09-02, a bare agent name does NOT resolve, which is why every dispatch string
# reads `ai-bridge:<role>` and why the section below asserts the namespace instead.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
PA="$TPL/plugin/agents"
[ -d "$PA" ] || { echo "plugin-agents.test: missing $PA" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

AGENTS="advisor auditor cataloguer devops-engineer failure-analyst project-manager qa-reviewer software-engineer"

fm() { # <file> <key> — frontmatter value from between the first `---` pair only
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {sub("^" k ":[ ]*", ""); print; exit}' "$1"
}

# =======================================================================================
echo "== 1. the plugin carries exactly the eight role agents, and is the only copy =="
# =======================================================================================
ok "plugin/agents carries exactly the eight role agents" \
  "$(ls "$PA" | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(printf '%s\n' $AGENTS | sort | tr '\n' ' ' | sed 's/ $//')"
# Phase 2's whole point. A second copy under symlink/ SHADOWS the plugin one in every
# stamped instance, so its return would silently reinstate the drift the parity section
# used to guard — and nothing else in this repo would notice.
ok "symlink/.claude/agents is retired — the plugin copies are the only copies" \
  "$([ -e "$TPL/symlink/.claude/agents" ] && echo no || echo yes)" yes

# =======================================================================================
echo "== 2. the frontmatter facts the migration stands on =="
# =======================================================================================
for a in $AGENTS; do
  ok "$a carries an explicit name:"                        "$(fm "$PA/$a.md" name)" "$a"
done
# By PRESENCE, not value: a key introducing a nested block (`hooks:` with indented
# children) has an empty scalar value, and a value check would wave it through.
fm_has() { # <file> <key> — yes/no
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {found=1; exit}
                 END {print (found ? "yes" : "no")}' "$1"
}
for a in $AGENTS; do
  bad=""
  for k in hooks mcpServers permissionMode; do
    [ "$(fm_has "$PA/$a.md" "$k")" = yes ] && bad="${bad:+$bad }$k"
  done
  ok "$a uses no field plugins cannot ship"               "$bad" ""
done
for a in $AGENTS; do
  ok "$a grants an explicit tools: allowlist"             "$([ -n "$(fm "$PA/$a.md" tools)" ] && echo yes || echo no)" yes
done

# =======================================================================================
echo "== 3. every dispatch string is NAMESPACED =="
# =======================================================================================
# The measured fact this whole slice turns on (2026-09-02, from a bare directory):
# `ai-bridge-v2:advisor` dispatched and replied; the BARE name did NOT resolve, which
# contradicts the plugin docs. So a document that tells an agent to dispatch a role by
# its bare name describes something that fails at runtime, and it fails SILENTLY — the
# caller sees "no such agent", never "you forgot the namespace".
#
# Scoped to the two documents that actually dispatch a role agent (the loop launcher and
# the audit skill) plus the tick, so a prose mention of a role's NAME anywhere else is
# not swept up. Each is checked from both directions: the namespaced form is present, and
# the old transition namespace is gone.
DISPATCHERS="plugin/skills/dispatch/SKILL.md plugin/skills/audit/SKILL.md plugin/agents/project-manager.md"
for d in $DISPATCHERS; do
  ok "$(basename "$(dirname "$d")")/$(basename "$d") names ai-bridge:" \
    "$(grep -cF 'ai-bridge:' "$TPL/$d" | awk '{print ($1 > 0 ? "yes" : "no")}')" yes
  ok "…and carries no ai-bridge-v2: dispatch string" \
    "$(grep -cF 'ai-bridge-v2:' "$TPL/$d" | awk '{print ($1 > 0 ? "no" : "yes")}')" yes
done
# The plugin's own name is what the namespace is derived from, so a rename of one without
# the other leaves twelve dispatch strings pointing at nothing.
ok "the namespace matches plugin.json's name" \
  "$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TPL/plugin/.claude-plugin/plugin.json" | head -1)" \
  "ai-bridge"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
