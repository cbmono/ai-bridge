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
#   2. ABSENCE IS SAFE, in the direction that matters. `rm -rf config/required` leaves
#      `--config` at exit 0 with nothing to link. `rm -rf config` leaves an INSTANCE stamp
#      completely unaffected — that is the AUTONOMY.md contract here — while `--config`
#      itself exits 2 naming what is missing, which is a refusal to do nothing rather than
#      a breakage, and is asserted as such further down.
#   3. NO WHOLE-DIRECTORY LINK FOR A DROP-IN DIRECTORY. agents/, commands/, skills/ and
#      friends receive new subdirectories from skill and plugin installers at any time.
#      Linking one as a unit aims it at this repo's working tree: that is how four
#      uninvited skills got committed to the parent repo on 2026-08-22, three of them
#      dangling symlinks its installer would then have pushed to every consumer. So every
#      link is per FILE, and the drop-in assertion below proves a fresh drop stays
#      outside the checkout — the property, not the implementation text.
#
# WHAT MOVED OUT, AND WHY THIS FILE SHRANK. `~/.claude` is owned by `cbmono/ai-setup` now;
# this layer ships only the three agents `symlink/` probes for. So the assertions about
# commands, hooks, scripts, output styles, MEMORY.md and settings.json are gone — those
# paths are not this repo's to install, and `tests/config-ownership.test.sh` fails if they
# come back. Two assertions arrived in their place, both about the handover itself: the
# links the OLD layer left behind must be retired, and a config dir whose `agents/` is a
# whole-directory symlink into ai-setup must be reported as already satisfied rather than
# refused — otherwise `--config` exits non-zero on the normal configuration and the order
# the two installers ran in decides the outcome. See docs/claude-config-ownership.md.
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
ok "every link resolves"                 "$(find "$D" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
# The paths this repo handed to ai-setup. Asserted absent rather than left unmentioned:
# "we stopped shipping them" and "the assertions were deleted" look identical otherwise.
for gone in commands/acp.md output-styles/brief.md hooks/statusline.sh scripts/codegraph-sync.sh MEMORY.md settings.json; do
  ok "ai-setup's $gone is NOT installed from here" "$(yn test -e "$D/$gone")" no
done
# A copy-from template linked into the config dir is clutter that dangles when the
# checkout moves; a README.md in agents/ would be linked as an agent definition.
printf '{}\n' > "$TPL/config/required/agents/settings.plugins.example.json"
printf 'doc\n' > "$TPL/config/required/agents/README.md"
D2="$(newdest 2)"; run_cfg "$D2" "$TPL" >/dev/null
ok "an *.example.json is NOT linked"     "$(yn test -e "$D2/agents/settings.plugins.example.json")" no
ok "a README.md is NOT linked"           "$(yn test -e "$D2/agents/README.md")" no
rm -f "$TPL/config/required/agents/README.md" "$TPL/config/required/agents/settings.plugins.example.json"

# =========================================================================== #
echo "-- property 3: no whole-directory link for a drop-in directory"
ok "agents/ is a real directory, not a link" "$(yn test -L "$D/agents")" no
# The trap itself: a third-party installer drops an agent into the config dir. With a
# whole-dir link that write lands INSIDE this checkout and gets committed to a public
# repo. Assert the property — the checkout is unchanged — not the linking style.
before="$(find "$TPL/config" | wc -l | tr -d ' ')"
printf 'x\n' > "$D/agents/uninvited.md"
mkdir -p "$D/agents/uninvited-dir" && printf 'x\n' > "$D/agents/uninvited-dir/x.md"
after="$(find "$TPL/config" | wc -l | tr -d ' ')"
ok "a dropped-in agent does not reach the checkout"  "$after" "$before"
ok "…nor does a dropped-in subdirectory"            "$(yn test -e "$TPL/config/required/agents/uninvited-dir")" no
ok "…and the drop-in landed in the config dir"      "$(yn test -f "$D/agents/uninvited.md")" yes

# =========================================================================== #
echo "-- idempotent, and never a silent replacement"
rm -rf "$D/agents/uninvited.md" "$D/agents/uninvited-dir"
ok "a second run exits 0"                "$(run_cfg "$D" "$TPL")" 0
ok "…reports the links as already there" "$(said 'already linked')" yes
ok "…and makes no new backups"           "$(find "$D" -name '*.bak.*' | wc -l | tr -d ' ')" 0
D3="$(newdest 3)"; mkdir -p "$D3/agents"
printf 'my own architect\n' > "$D3/agents/code-architect.md"
printf '{"permissions":{"allow":["Bash(mine:*)"]}}\n' > "$D3/settings.json"
ok "with a real file in the way: exits 0" "$(run_cfg "$D3" "$TPL")" 0
ok "…the real file is backed up"          "$(cat "$D3"/agents/code-architect.md.bak.* 2>/dev/null)" "my own architect"
ok "…and replaced by the link"            "$(yn test -L "$D3/agents/code-architect.md")" yes
# settings.json belongs to ai-setup. This layer must not link it, back it up, edit it, or
# even mention it: two installers writing the file that holds a human's permissions is the
# collision the ownership split removes.
ok "a real settings.json is left alone"   "$(cat "$D3/settings.json")" '{"permissions":{"allow":["Bash(mine:*)"]}}'
ok "…and is still not a symlink"          "$(yn test -L "$D3/settings.json")" no
ok "…and was not even mentioned"          "$(said 'settings.json')" no

# =========================================================================== #
echo "-- a symlinked directory in the way is never written through"
# CASE A — it provides nothing. ai-setup is not installed, or its agents/ does not hold the
# file: we cannot write it without writing into that other checkout, so refuse and say so.
D4="$(newdest 4)"; mkdir -p "$TMP/foreign/agents"
ln -s "$TMP/foreign/agents" "$D4/agents"
rc="$(run_cfg "$D4" "$TPL")"
ok "unprovided: exits non-zero"           "$([ "$rc" != 0 ] && echo yes || echo no)" yes
ok "…names the offending directory"       "$(said 'is a symlink')" yes
ok "…writes NOTHING into the other tree"  "$(find "$TMP/foreign/agents" -mindepth 1 | wc -l | tr -d ' ')" 0
ok "…and prints the mv that fixes it"     "$(said 'mv ')" yes

# CASE B — THE NORMAL CONFIGURATION. ai-setup links ~/.claude/agents as a whole directory
# and ships all three probed-for agents, so every entry here has a symlinked parent that
# already satisfies the requirement. Reporting that (rather than refusing) is what makes
# the two installers compose in either order; without it `--config` exits non-zero on any
# machine that ran ai-setup's installer.
D14="$(newdest 14)"; mkdir -p "$TMP/asetup/agents"
while IFS= read -r a; do
  [ -n "$a" ] || continue
  printf 'ai-setup copy of %s\n' "$a" > "$TMP/asetup/agents/$a"
done <<AGENTS
$(cd "$TPL/config/required/agents" && ls)
AGENTS
ln -s "$TMP/asetup/agents" "$D14/agents"
ok "provided elsewhere: exits 0"          "$(run_cfg "$D14" "$TPL")" 0
ok "…and says who provides it"            "$(said 'provided by')" yes
ok "…writes NOTHING into that checkout"   "$(find "$TMP/asetup/agents" -type l | wc -l | tr -d ' ')" 0
ok "…leaves the other copy in place"      "$(head -1 "$D14/agents/code-architect.md")" "ai-setup copy of code-architect.md"
ok "…and reports it separately from ours" "$(said 'provided by another config layer')" yes
# Non-vacuity for case B: with the file removed from the other checkout, the SAME config
# dir must go back to refusing. Otherwise "provided" would be a blanket pass on any
# symlinked parent, which is the guard this layer was built around.
rm -f "$TMP/asetup/agents/code-architect.md"
rc="$(run_cfg "$D14" "$TPL")"
ok "…and a gap in it is refused again"    "$([ "$rc" != 0 ] && echo yes || echo no)" yes
ok "…naming the directory, not the file"  "$(said 'is a symlink')" yes

# =========================================================================== #
echo "-- property 2: absence is safe"
# The tier is empty but present: nothing to link, and that is not an error.
T2="$TMP/tpl-emptytier"; make_tpl "$T2"; rm -f "$T2/config/required/agents/"*.md
D5="$(newdest 5)"
ok "an empty tier: exits 0"               "$(run_cfg "$D5" "$T2")" 0
ok "…and links nothing"                   "$(find "$D5" -type l | wc -l | tr -d ' ')" 0
ok "…and nothing is reported as an error" "$(said 'error')" no
# The tier is gone entirely. `config/` itself still exists, so this is the AUTONOMY.md
# contract: delete the directory, lose the capability, break nothing.
T3="$TMP/tpl-noreq"; make_tpl "$T3"; rm -rf "$T3/config/required"; mkdir -p "$T3/config"
D6="$(newdest 6)"
ok "no required tier at all: exits 0"     "$(run_cfg "$D6" "$T3")" 0
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
ln -s "$TMP/nowhere-at-all" "$D11/agents/foreign-dangling"
printf 'mine\n' > "$D11/agents/mine.md"
rm "$T5/config/required/agents/plan-architect.md"
ok "after retiring a file: exits 0"       "$(run_cfg "$D11" "$T5")" 0
ok "…the dangling link is gone"           "$(yn test -L "$D11/agents/plan-architect.md")" no
ok "…and it said so"                      "$(said 'retire agents/plan-architect.md')" yes
ok "a foreign dangling link survives"     "$(yn test -L "$D11/agents/foreign-dangling")" yes
ok "a real file survives"                 "$(yn test -f "$D11/agents/mine.md")" yes

# =========================================================================== #
echo "-- the handover: links from the layer this repo no longer ships are retired"
# The transition every existing machine goes through. Before the ownership split this
# layer linked ~23 more paths out of config/opinionated/; those files are gone, so the
# links dangle — a dangling command still registers with Claude Code and a dangling hook
# exits 127 on every launch. CONFIG_MANAGED_TOPS is what makes the sweep still LOOK in
# commands/, hooks/, scripts/ and output-styles/ now that nothing under config/ names
# them, which is why that list is never pruned.
D15="$(newdest 15)"; T7="$TMP/tpl-handover"; make_tpl "$T7"
run_cfg "$D15" "$T7" >/dev/null
# The target path must be spelled the way the INSTALLER spells it: it derives its source
# with `cd $(dirname $0) && pwd`, which normalises away a `//` that `$TMPDIR` happily
# carries, and the sweep matches by target PREFIX. A fixture that links to
# "$T7/config/..." while $TMP holds a double slash builds a link no real install could
# produce, and the sweep correctly declines to touch it.
SRC7="$(cd "$T7" && pwd)"
for old in commands/grill.md hooks/statusline.sh scripts/deepseek-session.sh output-styles/brief.md MEMORY.md settings.json; do
  mkdir -p "$D15/$(dirname "$old")"
  ln -s "$SRC7/config/opinionated/$old" "$D15/$old"   # the target never existed: same as removed
done
ok "the stale layer's links are in place" "$(find "$D15" -type l | wc -l | tr -d ' ')" 9
ok "a --config run exits 0"               "$(run_cfg "$D15" "$T7")" 0
ok "…every stale link is retired"         "$(find "$D15" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
# -L, not -e: `test -e` is already false for a DANGLING link, so an -e assertion here
# would pass without the sweep ever running — the exact shape of a decorative test.
ok "…including the top-level ones"        "$(yn test -L "$D15/MEMORY.md")" no
ok "…and settings.json's"                 "$(yn test -L "$D15/settings.json")" no
ok "…it said what it retired"             "$(said 'retire commands/grill.md')" yes
ok "…and the three we own are still there" "$(find "$D15/agents" -type l | wc -l | tr -d ' ')" 3

# =========================================================================== #
echo "-- uninstall removes only what it created"
D12="$(newdest 12)"; run_cfg "$D12" "$TPL" >/dev/null
printf 'mine\n' > "$D12/agents/mine.md"
ln -s "$TMP/elsewhere" "$D12/agents/foreign.md"
printf 'bak\n' > "$D12/agents/keep.bak.1"
ok "--config --uninstall exits 0"         "$(run_cfg "$D12" "$TPL" --uninstall)" 0
ok "…our links are gone"                  "$(yn test -e "$D12/agents/code-architect.md")" no
ok "…a real file survives"                "$(yn test -f "$D12/agents/mine.md")" yes
ok "…a foreign link survives"             "$(yn test -L "$D12/agents/foreign.md")" yes
ok "…a backup survives"                   "$(yn test -f "$D12/agents/keep.bak.1")" yes

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
