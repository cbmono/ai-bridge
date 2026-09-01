#!/usr/bin/env bash
#
# plugin-agents.test.sh — the eight role agents ship in the plugin, in BYTE-PARITY with
# the instance copies for as long as both exist.
#
# WHY PARITY IS THE CONTRACT, NOT A TRANSITION SMELL: agent precedence is the REVERSE of
# skills — a same-named project agent SHADOWS the plugin copy (plugins are the lowest
# scope). So the safe migration is two-phase: phase 1 ships the agents here while the
# instance links remain (instances win, zero behaviour change), and THIS FILE is what
# makes that window safe — two copies that cannot drift are one copy. Phase 2 deletes
# the symlink/ agents (with the install.sh sweep) once a plugin-agent dispatch has been
# measured in a fresh session; when it does, the parity section below dissolves into
# plain shape checks on the plugin copies, which become the only copies.
#
# The frontmatter section pins the two facts the migration was planned around: every
# agent carries an explicit `name:` (an explicit name resolves BARE, so no dispatch
# string anywhere changes), and none uses a field plugins cannot ship (hooks,
# mcpServers, permissionMode) — a field added later would vanish silently at phase 2.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
PA="$TPL/plugin/agents"
SA="$TPL/symlink/.claude/agents"
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
echo "== 1. the set is exact in both directions =="
# =======================================================================================
ok "plugin/agents carries exactly the eight role agents" \
  "$(ls "$PA" | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(printf '%s\n' $AGENTS | sort | tr '\n' ' ' | sed 's/ $//')"
if [ -d "$SA" ]; then
  ok "…and the instance side still carries the same eight (phase 1)" \
    "$(ls "$SA" | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')" \
    "$(printf '%s\n' $AGENTS | sort | tr '\n' ' ' | sed 's/ $//')"
fi

# =======================================================================================
echo "== 2. byte-parity while both copies exist — two copies that cannot drift are one =="
# =======================================================================================
if [ -d "$SA" ]; then
  for a in $AGENTS; do
    ok "$a: plugin copy is byte-identical to the instance copy" \
      "$(cmp -s "$PA/$a.md" "$SA/$a.md" && echo yes || echo no)" yes
  done
else
  echo "  NOTE  symlink/.claude/agents is retired — phase 2 has landed; parity is moot."
fi

# =======================================================================================
echo "== 3. the frontmatter facts the migration stands on =="
# =======================================================================================
for a in $AGENTS; do
  ok "$a carries an explicit name: (bare-name dispatch)"  "$(fm "$PA/$a.md" name)" "$a"
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

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
