#!/usr/bin/env bash
#
# seed-script-paths.test.sh — every script the seed names by path ships in
# plugin/scripts/, so a rename cannot strand the prose.
#
# WHY. A bundle is data-only: it has no `scripts/`, so the seed's `scripts/<x>.sh` and
# `"$AB/<x>.sh"` forms both resolve into the installed plugin. Nothing read them, and a
# human following one got `no such file or directory` (2026-09-06, commit-as.sh).
# Exit codes: 0 clean, 1 a named script does not ship, 2 the tree is not readable.
# Reasoning: ai-bridge-next/task-022.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/plugin/seed"
SCRIPTS="$REPO/plugin/scripts"
[ -d "$SEED" ]    || { echo "seed-script-paths.test: missing $SEED" >&2; exit 2; }
[ -d "$SCRIPTS" ] || { echo "seed-script-paths.test: missing $SCRIPTS" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/seed-script-paths.XXXXXX")" \
  || { echo "seed-script-paths.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# Both forms the seed uses to name a plugin script, reduced to basenames. A placeholder
# like `scripts/<x>.sh` carries no basename character class match, so it never appears.
named()   { grep -rhoE '(scripts|\$AB)/[A-Za-z0-9._-]+\.sh' "$1" | sed 's#.*/##' | sort -u; }
shipped() { find "$SCRIPTS" -maxdepth 1 -name '*.sh' -exec basename {} \; | sort; }
stranded() { comm -23 <(named "$1") <(shipped); }

echo
echo "== 1. the scan sees something on both sides =="
ok "the seed names scripts ($(named "$SEED" | wc -l | tr -d ' '))" \
   "$([ -n "$(named "$SEED")" ] && echo yes || echo no)" yes
ok "…and the plugin ships scripts"  "$([ -n "$(shipped)" ] && echo yes || echo no)" yes

echo
echo "== 2. every script the seed names ships =="
ok "no stranded reference ($(stranded "$SEED" | tr '\n' ' '))" \
   "$(stranded "$SEED" | wc -l | tr -d ' ')" 0

echo
echo "== 3. the seed defines what a bare path means — agent side and human side =="
ok "CLAUDE.md gives the agent resolution" \
   "$(grep -c 'CLAUDE_PLUGIN_ROOT}/scripts/' "$SEED/CLAUDE.md" | tr -d ' ')" 1
ok "…and the human one, versionless" \
   "$(grep -c 'plugins/cache/\*/ai-bridge/\*/scripts' "$SEED/CLAUDE.md" | tr -d ' ')" 1

echo
echo "== 4. the mutant goes RED — the check discriminates =="
cp -R "$SEED" "$TMP/seed"
printf 'run `scripts/no-such-script.sh` to break this test\n' >> "$TMP/seed/README.md"
ok "a renamed-away script is reported stranded" \
   "$(stranded "$TMP/seed" | grep -cx 'no-such-script.sh' | tr -d ' ')" 1

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
