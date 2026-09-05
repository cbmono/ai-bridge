#!/usr/bin/env bash
#
# companion-plugins.test.sh — the companion extension point: `resolve-autonomy.sh`'s
# resolution order against a FIXTURE companion root, the `ai-bridge-yolo` marketplace
# entry, and the one rule the whole design rests on — a companion may ADD behaviour but
# never remove a core gate.
#
# THE FAILURE THIS EXISTS FOR. `AUTONOMY.md` is the capability: found, a project's
# `autonomy:` field selects a mode; not found, both human gates hold absolutely. It used
# to be stamped to the bundle root from `symlink/`, and after ai-bridge-v2/task-013
# nothing stamps it — so the presence check survived with nothing left to make the file
# present. Turning that check into an extension point moves it from one `[ -f ]` to a
# lookup across a machine-level plugin registry, and every new way for that lookup to say
# "yes" is a new way for the loop to promote and merge without a human. So the cases below
# are weighted towards the answers that must stay NO.
#
# WHY A FIXTURE REGISTRY AND NOT THE REAL ONE. The real
# `~/.claude/plugins/installed_plugins.json` says whatever this machine happens to have
# installed, so a test that read it would pass or fail on a developer's install state and
# tell nobody anything. Every case here points `CLAUDE_CONFIG_DIR` at a registry this file
# wrote, so each answer is a property of the resolver.
#
# NON-VACUOUS BY CONSTRUCTION. The positive case (a companion IS found) runs against the
# same fixture as the negative ones and differs only in the one field under test — the
# marketplace suffix, the fixed relative path, the file's existence — so a resolver that
# said "no" to everything would fail here rather than passing three cases out of four.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVE="$REPO/plugin/scripts/resolve-autonomy.sh"
MJ="$REPO/.claude-plugin/marketplace.json"
YOLO="$REPO/plugin-yolo"
PLUGIN_README="$REPO/plugin/README.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/companion-plugins.XXXXXX")" || {
  echo "companion-plugins.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# NORMALISE IT. A TMPDIR with a trailing slash yields `…/tmp//companion-plugins.X`, and the
# resolver prints a `cd`-normalised path — so every expected string below would differ from
# the actual one by a slash nobody typed.
TMP="$(cd "$TMP" && pwd)" || { echo "companion-plugins.test: could not resolve $TMP" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------- the fixture machine
# A bundle with no AUTONOMY.md of its own, a config dir holding a registry, and a
# companion plugin root laid out the way the contract says.
BUNDLE="$TMP/bundle";      mkdir -p "$BUNDLE"
CFG="$TMP/cfg";            mkdir -p "$CFG/plugins"
COMPANION="$TMP/companion"; mkdir -p "$COMPANION/companion"
printf '# fixture capability file\n' > "$COMPANION/companion/AUTONOMY.md"
EMPTY="$TMP/empty-cfg";    mkdir -p "$EMPTY"

write_registry() { # <key> [<extra-key> <extra-path>]
  cat > "$CFG/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "$1": [
      {
        "scope": "user",
        "installPath": "$COMPANION",
        "version": "0.15.0",
        "installedAt": "2026-09-05T00:00:00.000Z"
      }
    ]
  }
}
JSON
}

# `resolve <config-dir>` — sets `out` to the resolver's stdout and `rc` to its exit
# status. NOT a function whose output is captured with `$( … )`: that runs it in a
# SUBSHELL, so the `rc` it assigns dies with the subshell and every caller reads the
# stale one. Measured here first time out — eight assertions comparing against an `rc`
# that never left 0.
out=""; rc=0
resolve() { out="$(CLAUDE_CONFIG_DIR="$1" "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?; }

echo
echo "== 1. absent both — every project is gated, exactly as before =="
# The floor. No file at the bundle root and no registry at all: exit 1, nothing on stdout.
# `commit-as.sh`'s promotion guard reads exactly this, so this case IS "both human gates
# hold" for a machine that has installed no companion.
resolve "$EMPTY"
ok "no bundle file, no registry -> exit 1"     "$rc" 1
ok "…and it prints nothing"                    "$([ -z "$out" ] && echo yes || echo no)" yes

# A registry that exists but lists no companion is the same answer by a different route:
# the machine has plugins, none of them ours.
write_registry "some-other-plugin@some-other-market"
resolve "$CFG"
ok "a registry listing no companion -> exit 1" "$rc" 1

echo
echo "== 2. an installed companion answers — the extension point itself =="
write_registry "ai-bridge-yolo@ai-bridge"
resolve "$CFG"
ok "companion installed -> exit 0"             "$rc" 0
ok "…and it prints that companion's file"      "$out" "$COMPANION/companion/AUTONOMY.md"

echo
echo "== 3. the bundle root WINS — a v1-era bundle keeps working unchanged =="
# The compatibility guarantee: a bundle carrying its own real AUTONOMY.md behaves byte for
# byte as it did, and no companion can override what it says. Asserted with the companion
# installed, because root-first is only meaningful when there is something to beat.
printf '# a v1-era bundle brought its own\n' > "$BUNDLE/AUTONOMY.md"
resolve "$CFG"
ok "root + companion -> exit 0"                "$rc" 0
ok "…and the ROOT file is what is returned"    "$out" "$BUNDLE/AUTONOMY.md"
# …and with no companion at all, which is the actual v1 machine.
resolve "$EMPTY"
ok "root alone, no registry -> exit 0"         "$rc" 0
ok "…still the root file"                      "$out" "$BUNDLE/AUTONOMY.md"
rm -f "$BUNDLE/AUTONOMY.md"

echo
echo "== 4. the three ways a lookup must still say NO =="
# (a) THE MARKETPLACE IS PART OF THE CONTRACT. Arming delegated authority must not be
#     reachable by an unrelated plugin someone installed for an unrelated reason, so a
#     plugin carrying the right path under the WRONG marketplace is not a companion.
write_registry "ai-bridge-yolo@somebody-elses-market"
resolve "$CFG"
ok "right path, wrong marketplace -> exit 1"   "$rc" 1

# (b) THE RELATIVE PATH IS FIXED. A file at the companion's plugin ROOT is not what core
#     reads — otherwise a companion's own README or docs could be mistaken for it.
write_registry "ai-bridge-yolo@ai-bridge"
mv "$COMPANION/companion/AUTONOMY.md" "$COMPANION/AUTONOMY.md"
resolve "$CFG"
ok "file at the plugin root, not companion/ -> exit 1" "$rc" 1
mv "$COMPANION/AUTONOMY.md" "$COMPANION/companion/AUTONOMY.md"

# (c) UNINSTALLED MEANS OFF, which is the whole design and the reason the resolver reads
#     the registry rather than the plugin CACHE tree: the cache keeps every version ever
#     fetched, uninstalled ones included, so a cache scan would answer "installed"
#     forever. Modelled by leaving the companion's files exactly where they are and
#     removing only its registry entry.
write_registry "some-other-plugin@some-other-market"
resolve "$CFG"
ok "files on disk but no registry entry -> exit 1" "$rc" 1
ok "…and the companion's file is still there (so this proves the registry decided)" \
   "$(yn test -f "$COMPANION/companion/AUTONOMY.md")" yes

echo
echo "== 5. commit-as.sh's promotion guard reads the same lookup =="
# The guard is where the extension point has teeth: it decides whether an agent-role
# commit may carry `status: ready`. One reader, so the guard and the loop cannot come to
# disagree about whether delegation exists at all.
ok "commit-as.sh calls resolve-autonomy.sh" \
   "$(grep -c 'resolve-autonomy.sh' "$REPO/plugin/scripts/commit-as.sh" | tr -d ' ')" 2
ok "…and still falls back to the root-only check it used to be" \
   "$(grep -c '\[ -f "\$repo_root/AUTONOMY.md" \] && delegation_possible=1' "$REPO/plugin/scripts/commit-as.sh" | tr -d ' ')" 1

echo
echo "== 6. ai-bridge-yolo is a real, installable marketplace entry =="
if command -v jq >/dev/null 2>&1; then
  ok "the marketplace lists ai-bridge-yolo" \
     "$(jq -r '[.plugins[].name] | index("ai-bridge-yolo") | if . == null then "no" else "yes" end' "$MJ")" yes
  SRC="$(jq -r '.plugins[] | select(.name=="ai-bridge-yolo") | .source' "$MJ")"
  ok "…its source is a same-repo relative path" "$(printf '%s' "$SRC" | grep -c '^\./' | tr -d ' ')" 1
  ok "…which resolves to a plugin manifest" \
     "$(yn test -f "$REPO/${SRC#./}/.claude-plugin/plugin.json")" yes
  ok "…whose name matches the entry" "$(jq -r .name "$REPO/${SRC#./}/.claude-plugin/plugin.json")" "ai-bridge-yolo"
  ok "…and whose versions agree" \
     "$([ "$(jq -r .version "$REPO/${SRC#./}/.claude-plugin/plugin.json")" \
        = "$(jq -r '.plugins[] | select(.name=="ai-bridge-yolo") | .version' "$MJ")" ] && echo yes || echo no)" yes
  # The deprecation stub was removed at 1.0.0 (ai-bridge-v2/task-019) after its one
  # version. Asserted from this file too, because the entry sat NEXT to the companion's
  # and a re-add would silently restore an install path for a name nothing maintains.
  ok "the ai-bridge-v2 stub entry is gone" \
     "$(jq -r '[.plugins[].name] | index("ai-bridge-v2") | if . == null then "no" else "yes" end' "$MJ")" no
  ok "…and ai-bridge is still plugins[0]" "$(jq -r '.plugins[0].name' "$MJ")" "ai-bridge"
else
  echo "  SKIP  jq not installed — the manifest checks need it"
fi

# The vendor's own validator, when present. It is the closest thing to "installable" that
# can be answered before the entry is on the default branch: `/plugin install` resolves the
# marketplace from the REMOTE, so the install itself is only exercisable after merge — and
# actually installing it here would arm delegated autonomy on this machine, which is a
# decision, not a test step.
if command -v claude >/dev/null 2>&1; then
  vout="$(claude plugin validate "$YOLO" --strict 2>&1)"; vrc=$?
  ok "claude plugin validate --strict passes on plugin-yolo" "$vrc" 0
  [ "$vrc" -eq 0 ] || printf '%s\n' "$vout" | sed 's/^/        | /'
else
  echo "  SKIP  claude CLI not on PATH — the jq manifest checks above still hold"
fi

echo
echo "== 7. the companion ships the capability file AND NOTHING ELSE core needs =="
ok "plugin-yolo/companion/AUTONOMY.md exists" "$(yn test -f "$YOLO/companion/AUTONOMY.md")" yes
ok "…at the fixed relative path the resolver reads" \
   "$(grep -c 'COMPANION_REL="companion/AUTONOMY.md"' "$RESOLVE" | tr -d ' ')" 1
ok "…and it is the type SCHEMA.md gives it" \
   "$(grep -c '^type: Reference$' "$YOLO/companion/AUTONOMY.md" | tr -d ' ')" 1
# A companion shipping a second copy of a PreToolUse enforcement hook would fire it in
# every session on the machine; a second agent set would shadow the real one.
ok "ships no hooks"   "$(yn test -e "$YOLO/hooks")"   no
ok "ships no agents"  "$(yn test -e "$YOLO/agents")"  no
ok "ships no skills"  "$(yn test -e "$YOLO/skills")"  no
ok "ships no scripts" "$(yn test -e "$YOLO/scripts")" no
# The core file is gone from where the template used to keep it: one copy, never two.
ok "core no longer carries a capability file" "$(yn test -e "$REPO/docs/autonomy")" no

echo
echo "== 8. the contract is documented where a companion author would look =="
ok "plugin/README.md has a Companion plugins section" \
   "$(grep -c '^## Companion plugins$' "$PLUGIN_README" | tr -d ' ')" 1
# The three things criterion 1 asks the contract to state. Matched on the substantive
# words rather than a whole sentence, so a rewrite that keeps the rule keeps the test.
ok "…it says how a companion registers (a marketplace entry)" \
   "$(grep -c 'marketplace.json' "$PLUGIN_README" | tr -d ' ')" 1
ok "…it names the fixed relative path core reads" \
   "$(grep -c 'companion plugin root>/companion/' "$PLUGIN_README" | tr -d ' ')" 1
ok "…and it states the ADD-never-remove rule" \
   "$(grep -c 'may ADD behaviour' "$PLUGIN_README" | tr -d ' ')" 1
ok "…naming the thing that may not be removed" \
   "$(grep -c 'remove a core gate' "$PLUGIN_README" | tr -d ' ')" 2
# The rule is only worth anything if the gates it protects are still there with NO
# companion installed, which is section 1 above plus this: core seeds the deny baseline
# and SCHEMA.md's two human authorities regardless of what is installed.
ok "…and core still states the two human authorities" \
   "$(grep -c 'Two human authorities' "$REPO/plugin/seed/SCHEMA.md" | tr -d ' ')" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
