#!/usr/bin/env bash
#
# config-layer.test.sh — `install.sh --config` links the ~/.claude layer, and the two
# halves of this repo stay independent in both directions.
#
# WHY. ai-bridge had four dependencies on a separate config repo and all four failed
# SILENTLY: the `@~/.claude/claude-defaults.md` import every instance inherited from
# seed/CLAUDE.md, and three probed-for agents (`code-architect`, `deep-bug-scan`,
# `plan-architect`). Folding that layer in is only worth doing if three properties hold,
# and each of them is a property nothing else in the suite would notice breaking:
#
#   1. THE ARROW STAYS ONE-WAY. `symlink/` must never *require* `config/`. A stamp on a
#      machine that never ran `--config` — or from a checkout with no `config/` at all —
#      must produce a working instance. That is what makes this modular and not merely
#      bundled, so it is asserted directly rather than inferred from the probes.
#   2. ABSENCE IS SAFE. `rm -rf config/opinionated` (or `config/required`) must break
#      nothing and error nowhere. Same contract as AUTONOMY.md, applied to a directory.
#   3. NO WHOLE-DIRECTORY LINK FOR A DROP-IN DIRECTORY. agents/, commands/, skills/ and
#      friends receive new subdirectories from skill and plugin installers at any time.
#      Linking one as a unit aims it at this repo's working tree: that is how four
#      uninvited skills got committed to the parent repo on 2026-08-22, three of them
#      dangling symlinks its installer would then have pushed to every consumer. So every
#      link is per FILE, and the drop-in assertion below proves a fresh drop stays
#      outside the checkout — the property, not the implementation text.
#
# ok() compares actual to expected, in that argument order, per this directory's
# convention. Inverting it is the mistake this codebase keeps making: a command that
# fails for the WRONG reason becomes a pass through a negated helper.
#
# Every fixture is a throwaway copy of the template under mktemp, with
# CLAUDE_CONFIG_DIR pointed at a throwaway directory — the real ~/.claude and the real
# instances are never touched.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/configlayer.XXXXXX")"
trap 'git -C "$TMP/wtmain" worktree remove --force "$TMP/wtlinked" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# A copy of the template carrying the REAL config/ tree, so the tier contents under test
# are the ones that ship. symlink/ and seed/ are minimal — this file is about the config
# half, and the instance half has its own harnesses.
make_tpl() { # <dir>
  local d="$1"
  mkdir -p "$d/symlink/scripts" "$d/seed"
  cp "$REPO/install.sh" "$d/install.sh"
  cp -R "$REPO/config" "$d/config"
  printf '{}\n' > "$d/seed/instance.config.json"
  # The REAL seed CLAUDE.md, so the stale-import nudge is exercised against the content a
  # fresh instance actually gets — its replacement section quotes the old import line.
  cp "$REPO/seed/CLAUDE.md" "$d/seed/CLAUDE.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/symlink/scripts/s.sh"
  printf 'x\n' > "$d/symlink/SCHEMA.md"
}
newdest() { local d="$TMP/dest$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
run_cfg() {  # <dest> <tpl> [extra args…] → exit code
  local dest="$1" tpl="$2"; shift 2
  CLAUDE_CONFIG_DIR="$dest" bash "$tpl/install.sh" --config "$@" >"$TMP/out" 2>&1
  printf '%s' "$?"
}
said() { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
# Files the layer is expected to link: every file in either tier except the two kinds
# that are never linked (a repo README, a copy-from *.example.json template).
linkable() { # <tpl>
  find "$1/config" -type f 2>/dev/null \
    | grep -v '/README\.md$' | grep -v '\.example\.json$' | wc -l | tr -d ' '
}

TPL="$TMP/tpl"; make_tpl "$TPL"

# =========================================================================== #
echo "-- the four silent dependencies are actually closed"
# The hard one: the import is gone from the seed and the content is inlined. An @import
# that resolves to nothing is a no-op, so only a content assertion can see this.
# An import LINE, not the string: the replacement section quotes the old import inside a
# comment explaining why it went, and matching that would assert the opposite of the point.
ok "seed/CLAUDE.md no longer imports claude-defaults" \
   "$(grep -qE '^[[:space:]]*@~/\.claude/claude-defaults\.md' "$REPO/seed/CLAUDE.md" && echo yes || echo no)" no
ok "…and carries the session defaults inline" \
   "$(grep -q '^### Planning & thinking' "$REPO/seed/CLAUDE.md" && echo yes || echo no)" yes
# Every agent the machinery probes for by absolute path must be in the REQUIRED tier.
# Derived from the probes rather than hard-coded, so a new probe added to a role agent
# without a matching agent file fails here instead of failing silently in a session.
probed="$(grep -rhoE '~/\.claude/agents/[a-z0-9-]+\.md' "$REPO/symlink" 2>/dev/null \
          | sed 's#.*/##' | sort -u)"
ok "the machinery probes for at least one agent" "$([ -n "$probed" ] && echo yes || echo no)" yes
missing=0
while IFS= read -r a; do
  [ -n "$a" ] || continue
  [ -f "$REPO/config/required/agents/$a" ] || { missing=$((missing+1)); printf '        MISSING  %s\n' "$a"; }
done <<EOF
$probed
EOF
ok "every probed agent ships in config/required" "$missing" 0
# project-manager.md names plan-architect in prose rather than in a `test -f`, so the
# regex above cannot see it. Asserted by name, since it is one of the four dependencies.
ok "plan-architect ships in config/required" \
   "$(yn test -f "$REPO/config/required/agents/plan-architect.md")" yes
# And the probes themselves must SURVIVE — they are what makes a config-less machine work.
ok "qa-reviewer still probes rather than assuming" \
   "$(grep -q 'test -f ~/.claude/agents/code-architect.md' "$REPO/symlink/.claude/agents/qa-reviewer.md" && echo yes || echo no)" yes

# =========================================================================== #
echo "-- a fresh config install"
D="$(newdest 1)"
ok "--config exits 0"                    "$(run_cfg "$D" "$TPL")" 0
ok "…links every linkable file"          "$(find "$D" -type l | wc -l | tr -d ' ')" "$(linkable "$TPL")"
ok "…including the required agents"      "$(yn test -L "$D/agents/code-architect.md")" yes
ok "…and the opinionated commands"       "$(yn test -L "$D/commands/acp.md")" yes
ok "…and the output style"               "$(yn test -L "$D/output-styles/brief.md")" yes
ok "…and the hooks"                      "$(yn test -L "$D/hooks/statusline.sh")" yes
ok "…and the scripts"                    "$(yn test -L "$D/scripts/codegraph-sync.sh")" yes
ok "…and MEMORY.md"                      "$(yn test -L "$D/MEMORY.md")" yes
ok "…and settings.json (none was there)" "$(yn test -L "$D/settings.json")" yes
ok "every link resolves"                 "$(find "$D" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
# A copy-from template linked into the config dir is clutter that dangles when the
# checkout moves; a README.md in commands/ would register as the command `/README`.
ok "an *.example.json is NOT linked"     "$(yn test -e "$D/settings.plugins.example.json")" no
printf 'doc\n' > "$TPL/config/opinionated/commands/README.md"
D2="$(newdest 2)"; run_cfg "$D2" "$TPL" >/dev/null
ok "a README.md is NOT linked"           "$(yn test -e "$D2/commands/README.md")" no
rm -f "$TPL/config/opinionated/commands/README.md"

# =========================================================================== #
echo "-- property 3: no whole-directory link for a drop-in directory"
for d in agents commands hooks scripts output-styles skills; do
  ok "$d/ is a real directory, not a link" "$(yn test -L "$D/$d")" no
done
ok "skills/test-locators/ is a real directory too" "$(yn test -L "$D/skills/test-locators")" no
ok "…and its SKILL.md is the link"                 "$(yn test -L "$D/skills/test-locators/SKILL.md")" yes
# The trap itself: a third-party installer drops a skill into the config dir. With a
# whole-dir link that write lands INSIDE this checkout and gets committed to a public
# repo. Assert the property — the checkout is unchanged — not the linking style.
before="$(find "$TPL/config" | wc -l | tr -d ' ')"
mkdir -p "$D/skills/uninvited" && printf 'x\n' > "$D/skills/uninvited/SKILL.md"
mkdir -p "$D/agents" && printf 'x\n' > "$D/agents/uninvited.md"
after="$(find "$TPL/config" | wc -l | tr -d ' ')"
ok "a dropped-in skill does not reach the checkout" "$after" "$before"
ok "…nor does a dropped-in agent"                   "$(yn test -e "$TPL/config/opinionated/agents/uninvited.md")" no
ok "…and the drop-in landed in the config dir"      "$(yn test -f "$D/skills/uninvited/SKILL.md")" yes

# =========================================================================== #
echo "-- idempotent, and never a silent replacement"
rm -rf "$D/skills/uninvited" "$D/agents/uninvited.md"
ok "a second run exits 0"                "$(run_cfg "$D" "$TPL")" 0
ok "…reports the links as already there" "$(said 'already linked')" yes
ok "…and makes no new backups"           "$(find "$D" -name '*.bak.*' | wc -l | tr -d ' ')" 0
D3="$(newdest 3)"; mkdir -p "$D3/commands"
printf 'my own acp\n' > "$D3/commands/acp.md"
printf '{"permissions":{"allow":["Bash(mine:*)"]}}\n' > "$D3/settings.json"
ok "with a real file in the way: exits 0" "$(run_cfg "$D3" "$TPL")" 0
ok "…the real file is backed up"          "$(cat "$D3"/commands/acp.md.bak.* 2>/dev/null)" "my own acp"
ok "…and replaced by the link"            "$(yn test -L "$D3/commands/acp.md")" yes
# settings.json is the one file that can hold permissions and plugins a human tuned by
# hand, so it is never moved aside and never edited — only reported.
ok "a real settings.json is left alone"   "$(cat "$D3/settings.json")" '{"permissions":{"allow":["Bash(mine:*)"]}}'
ok "…and is still not a symlink"          "$(yn test -L "$D3/settings.json")" no
ok "…with the adopt commands printed"     "$(said 'ln -s')" yes

# =========================================================================== #
echo "-- a symlinked directory in the way is refused, never written through"
D4="$(newdest 4)"; mkdir -p "$TMP/foreign/agents"
ln -s "$TMP/foreign/agents" "$D4/agents"
rc="$(run_cfg "$D4" "$TPL")"
ok "it exits non-zero"                    "$([ "$rc" != 0 ] && echo yes || echo no)" yes
ok "…names the offending directory"       "$(said 'is a symlink')" yes
ok "…writes NOTHING into the other tree"  "$(find "$TMP/foreign/agents" -mindepth 1 | wc -l | tr -d ' ')" 0
ok "…and links the rest anyway"           "$(yn test -L "$D4/commands/acp.md")" yes

# =========================================================================== #
echo "-- property 2: absence is safe"
T2="$TMP/tpl-noopin"; make_tpl "$T2"; rm -rf "$T2/config/opinionated"
D5="$(newdest 5)"
ok "no opinionated tier: exits 0"         "$(run_cfg "$D5" "$T2")" 0
ok "…required tier still linked"          "$(yn test -L "$D5/agents/plan-architect.md")" yes
ok "…and nothing is reported as an error" "$(said 'error')" no
T3="$TMP/tpl-noreq"; make_tpl "$T3"; rm -rf "$T3/config/required"
D6="$(newdest 6)"
ok "no required tier: exits 0"            "$(run_cfg "$D6" "$T3")" 0
ok "…opinionated tier still linked"       "$(yn test -L "$D6/commands/grill.md")" yes
ok "…and nothing is reported as an error" "$(said 'error')" no

# =========================================================================== #
echo "-- property 1: the dependency arrow stays one-way"
T4="$TMP/tpl-nocfg"; make_tpl "$T4"; rm -rf "$T4/config"
I="$TMP/inst-nocfg"; mkdir -p "$I"
bash "$T4/install.sh" "$I" >"$TMP/out" 2>&1; irc=$?
ok "a config-less checkout still stamps"  "$irc" 0
ok "…the instance is seeded"              "$(yn test -f "$I/instance.config.json")" yes
ok "…and the machinery is linked"         "$(yn test -L "$I/SCHEMA.md")" yes
ok "--config there says so, exit 2"       "$(run_cfg "$(newdest 7)" "$T4")" 2
ok "…and explains what is missing"        "$(said 'no config layer')" yes
# The other direction: a config install must not touch an instance, and an instance
# install must not write into the config dir.
D8="$(newdest 8)"; I2="$TMP/inst-clean"; mkdir -p "$I2"
CLAUDE_CONFIG_DIR="$D8" bash "$TPL/install.sh" "$I2" >"$TMP/out" 2>&1
ok "an instance stamp writes nothing into the config dir" \
   "$(find "$D8" -mindepth 1 | wc -l | tr -d ' ')" 0

# =========================================================================== #
echo "-- the bare-TARGET interface is unchanged"
I3="$TMP/inst-bare"; mkdir -p "$I3"
bash "$TPL/install.sh" "$I3" >"$TMP/out" 2>&1
ok "bare TARGET still stamps an instance" "$(yn test -f "$I3/instance.config.json")" yes
I4="$TMP/inst-flag"; mkdir -p "$I4"
bash "$TPL/install.sh" --instance "$I4" >"$TMP/out" 2>&1
ok "--instance TARGET does the same"      "$(yn test -f "$I4/instance.config.json")" yes
bash "$TPL/install.sh" --config "$I4" >"$TMP/out" 2>&1
ok "--config with a target is refused"    "$?" 2
bash "$TPL/install.sh" --config --instance >"$TMP/out" 2>&1
ok "--config --instance is refused"       "$?" 2
ok "…as mutually exclusive"               "$(said 'mutually exclusive')" yes
# --help is generated by a LINE RANGE over this script's own header, which truncates
# silently when the header grows. These assertions are what notices.
bash "$TPL/install.sh" --help >"$TMP/out" 2>&1
ok "--help documents --config"            "$(said -- '--config')" yes
ok "--help documents --instance"          "$(said -- '--instance')" yes
ok "--help is not truncated"              "$(said 'Backs up any conflicting real file')" yes

# =========================================================================== #
echo "-- the worktree guard covers --config too"
WM="$TMP/wtmain"; make_tpl "$WM"
( cd "$WM" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
git -C "$WM" worktree add -q "$TMP/wtlinked" -b wt >/dev/null 2>&1
D9="$(newdest 9)"
ok "--config from a worktree exits 2"     "$(run_cfg "$D9" "$TMP/wtlinked")" 2
ok "…says why"                            "$(said 'refusing to install from a git worktree')" yes
ok "…and linked nothing"                  "$(find "$D9" -mindepth 1 | wc -l | tr -d ' ')" 0
ok "--config from the main tree works"    "$(run_cfg "$(newdest 10)" "$WM")" 0

# =========================================================================== #
echo "-- retiring a config file sweeps its dangling link"
D11="$(newdest 11)"; T5="$TMP/tpl-retire"; make_tpl "$T5"
run_cfg "$D11" "$T5" >/dev/null
ln -s "$TMP/nowhere-at-all" "$D11/commands/foreign-dangling"
printf 'mine\n' > "$D11/commands/mine.md"
rm "$T5/config/opinionated/commands/rabbit.md"
ok "after retiring a file: exits 0"       "$(run_cfg "$D11" "$T5")" 0
ok "…the dangling link is gone"           "$(yn test -L "$D11/commands/rabbit.md")" no
ok "…and it said so"                      "$(said 'retire commands/rabbit.md')" yes
ok "a foreign dangling link survives"     "$(yn test -L "$D11/commands/foreign-dangling")" yes
ok "a real file survives"                 "$(yn test -f "$D11/commands/mine.md")" yes

# =========================================================================== #
echo "-- uninstall removes only what it created"
D12="$(newdest 12)"; run_cfg "$D12" "$TPL" >/dev/null
printf 'mine\n' > "$D12/agents/mine.md"
ln -s "$TMP/elsewhere" "$D12/agents/foreign.md"
printf 'bak\n' > "$D12/agents/keep.bak.1"
ok "--config --uninstall exits 0"         "$(run_cfg "$D12" "$TPL" --uninstall)" 0
ok "…our links are gone"                  "$(yn test -e "$D12/agents/code-architect.md")" no
ok "…settings.json link is gone"          "$(yn test -e "$D12/settings.json")" no
ok "…a real file survives"                "$(yn test -f "$D12/agents/mine.md")" yes
ok "…a foreign link survives"             "$(yn test -L "$D12/agents/foreign.md")" yes
ok "…a backup survives"                   "$(yn test -f "$D12/agents/keep.bak.1")" yes

# =========================================================================== #
echo "-- both tiers claiming one path is refused before any write"
T6="$TMP/tpl-dup"; make_tpl "$T6"
mkdir -p "$T6/config/required/commands"
cp "$T6/config/opinionated/commands/acp.md" "$T6/config/required/commands/acp.md"
D13="$(newdest 13)"
ok "a duplicated path exits 2"            "$(run_cfg "$D13" "$T6")" 2
ok "…names the path"                      "$(said 'commands/acp.md')" yes
ok "…and linked nothing at all"           "$(find "$D13" -mindepth 1 | wc -l | tr -d ' ')" 0

# =========================================================================== #
echo "-- an instance carrying the old import is told, not edited"
I5="$TMP/inst-stale"; mkdir -p "$I5"
bash "$TPL/install.sh" "$I5" >"$TMP/out" 2>&1
# A FRESH instance gets the inlined section, whose comment quotes the old import to
# explain it. An unanchored match would nag every new instance — the false-positive half.
ok "a freshly stamped instance is not nagged" "$(said 'still imports')" no
printf '# mine\n\n## Session defaults\n@~/.claude/claude-defaults.md\n' > "$I5/CLAUDE.md"
sum_before="$(cat "$I5/CLAUDE.md")"
bash "$TPL/install.sh" "$I5" >"$TMP/out" 2>&1
ok "the stale import is reported"         "$(said 'still imports ~/.claude/claude-defaults.md')" yes
ok "…the exact replacement is named"      "$(said 'Session defaults')" yes
ok "…and CLAUDE.md is NOT rewritten"      "$(cat "$I5/CLAUDE.md")" "$sum_before"
printf '# mine\n\n## Session defaults\n\n### Planning & thinking\n' > "$I5/CLAUDE.md"
bash "$TPL/install.sh" "$I5" >"$TMP/out" 2>&1
ok "an up-to-date instance is not nagged" "$(said 'still imports')" no

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
