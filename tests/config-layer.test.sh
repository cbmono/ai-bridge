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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/configlayer.XXXXXX")" || {
  echo "config-layer.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
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
# ONE argument, and `--` is already supplied here so a pattern starting with `-` is safe
# to pass plainly. Call it as `said '--config'`, never `said -- '--config'`: the extra `--`
# becomes "$1", the pattern is silently discarded, and the assertion can never fail.
said() { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
# Files the layer is expected to link: every file in the tier except the kinds that are
# never linked. It must mirror `config_entries()`'s exclusion list EXACTLY, or the count
# assertion below fails naming nothing useful. Two were missing: `settings.json` (ai-setup's
# file — a re-forked copy here would make this read one too many) and `.DS_Store`, which
# `make_tpl`'s `cp -R` copies straight out of the real checkout on macOS, so a Finder visit
# to `config/` turned this suite red with "links every linkable file — got 3, want 4".
linkable() { # <tpl>
  find "$1/config" -type f 2>/dev/null \
    | grep -v '/README\.md$' | grep -v '\.example\.json$' \
    | grep -v '/settings\.json$' | grep -v '/\.DS_Store$' | wc -l | tr -d ' '
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
   "$(grep -q 'test -f ~/.claude/agents/code-architect.md' "$REPO/plugin/agents/qa-reviewer.md" && echo yes || echo no)" yes

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
# The `--` belongs to grep, INSIDE said(), and passing a second one here was the whole
# defect: said() reads only "$1", so `said -- '--config'` grepped for a literal `--` and
# matched any --help output at all. Both assertions were unfalsifiable — deleting the
# `--instance` header line left the suite at 87 passed, 0 failed, this assertion included.
ok "--help documents --config"            "$(said '--config')" yes
ok "--help documents --instance"          "$(said '--instance')" yes
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
# layer linked 21 more paths out of config/opinionated/; those files are gone, so the
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
# A user whose 19 links just vanished is owed the name of the repo that ships them now.
# Asserted on the handover run specifically, and asserted ABSENT on a steady-state run, so
# it cannot become unconditional noise.
ok "…and it names the repo they moved to"  "$(said 'cbmono/ai-setup')" yes
# A DANGLING-LINK AUDIT SCORES THIS HANDOVER PERFECT AND A FILE IS GONE. Asserted as two
# numbers in one place, because "0 dangling" was cited twice as evidence that nothing was
# lost and it cannot be that: a path that was never linked is ABSENT, not dangling, so the
# count is structurally blind to exactly the failure it was quoted against. On a real
# machine this is not hypothetical — `settings.json`, carrying the 25-rule permissions.deny
# block, went missing in the ai-setup-first order with 0 dangling and exit 0. The check that
# CAN see it is presence over an enumerated owned set: `tests/config-ownership.test.sh`'s
# cross-repo group does it by membership here, and ai-setup's own harness does it per path.
ok "…the dangling audit reports a clean handover" \
   "$(find "$D15" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
# `test -e` was the assertion here, and it CANNOT FAIL: it is already false for a dangling
# link, so it read "no" before the sweep ran as well as after — a decorative test inside the
# group whose whole subject is decorative tests. `find -name` sees the entry itself whether
# or not it resolves, so it counts 1 before the sweep and 0 after: the number moves with the
# behaviour, which is the only thing that makes it an assertion.
ok "…while a path it retired is simply ABSENT" \
   "$(find "$D15" -maxdepth 1 -name settings.json | wc -l | tr -d ' ')" 0
ok "…and the sweep is what took it"        "$(said 'retire settings.json')" yes
ok "…so 0 dangling is not 0 lost"          "$(yn test -L "$D15/settings.json")" no
run_cfg "$D15" "$T7" >/dev/null
ok "a steady-state run stays quiet about it" "$(said 'cbmono/ai-setup')" no

# --------------------------------------------------------------------------- #
echo "-- …and it survives a SPACE in the config dir path"
# `~/Library/Application Support/claude` is an ordinary thing to set CLAUDE_CONFIG_DIR to,
# and no other fixture in this suite uses a path with a space — which is exactly why an
# unquoted `find $roots` in config_sweep, behind a `# shellcheck disable=SC2086`, survived
# review. Measured before the fix on the real in-place upgrade path: 21 retired / 0
# dangling without a space, and 2 retired / 19 dangling / exit 0 / no warning with one. The
# two survivors were the top-level entries, whose find call was already quoted — so an
# assertion on the top level alone would have passed throughout. This one counts what is
# left under the SUBDIRECTORIES.
D16="$TMP/dest 16 with spaces"; rm -rf "$D16"; mkdir -p "$D16"
T8="$TMP/tpl-handover-space"; make_tpl "$T8"
run_cfg "$D16" "$T8" >/dev/null
SRC8="$(cd "$T8" && pwd)"
for old in commands/grill.md hooks/statusline.sh scripts/deepseek-session.sh output-styles/brief.md MEMORY.md settings.json; do
  mkdir -p "$D16/$(dirname "$old")"
  ln -s "$SRC8/config/opinionated/$old" "$D16/$old"
done
ok "with a space: a --config run exits 0"  "$(run_cfg "$D16" "$T8")" 0
ok "…the SUBDIRECTORY links are retired"   "$(find "$D16" -mindepth 2 -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
ok "…and the top-level ones too"           "$(find "$D16" -maxdepth 1 -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" 0
ok "…it retired the subdirectory entries"  "$(said 'retire commands/grill.md')" yes
ok "…and the three we own are still there" "$(find "$D16/agents" -type l | wc -l | tr -d ' ')" 3

# --------------------------------------------------------------------------- #
echo "-- a write that FAILS is a failure, not a count"
# `ln -s` was unchecked while the `link`/counter lines ran regardless, and `set -e` cannot
# see it: the sole caller is `config_install || config_rc=$?`, which suspends errexit for
# the whole function. Measured before the fix with agents/ at mode 500: three Permission
# denied on stderr, "Done. 3 linked", exit 0, and zero links created. With `test -f` probes
# as the only consumers, a false "3 linked" is invisible for the rest of the session.
D17="$(newdest 17)"; mkdir -p "$D17/agents"; chmod 500 "$D17/agents"
rc17="$(run_cfg "$D17" "$TPL")"
ok "an unwritable dir: exits non-zero"     "$([ "$rc17" != 0 ] && echo yes || echo no)" yes
ok "…and reports 0 linked, not 3"          "$(said 'Done. 0 linked')" yes
ok "…names each file it could not write"   "$(grep -c '  fail  agents/' "$TMP/out" | tr -d ' ')" 3
ok "…and created no link at all"           "$(find "$D17" -type l | wc -l | tr -d ' ')" 0
chmod 700 "$D17/agents"

# --------------------------------------------------------------------------- #
echo "-- …and the SWEEP is a write too, so it is counted the same way"
# The group above is titled for a RULE and covered one caller. `config_install`'s three
# writes were checked while `config_sweep`'s `rm -f` was not — same round, same script, and
# in the half this split promotes from a tidiness pass to THE handover mechanism for ~21
# paths. Measured on a real in-place upgrade with `commands/` at mode 500: 21 `retire` lines
# and "Those 21 path(s) … moved" for 11 actual removals, exit 0, and ten dangling commands
# (/acp, /grill, /plan, /verify …) still registered with Claude Code. The only signal was
# `rm:` on stderr, under a success epilogue naming a repo to reinstall from. So this group
# repeats the same three assertions — non-zero exit, a count that matches reality, a named
# failure per path — plus the one only a sweep needs: what it could not retire is still on
# disk, and it said so.
D18="$(newdest 18)"; T9="$TMP/tpl-sweep-fail"; make_tpl "$T9"
run_cfg "$D18" "$T9" >/dev/null
SRC9="$(cd "$T9" && pwd)"
# Three under the directory that will be unwritable and four elsewhere: a fixture where the
# sweep fails on EVERYTHING cannot distinguish an accurate count from a suppressed one.
for old in commands/grill.md commands/acp.md commands/plan.md \
           hooks/statusline.sh output-styles/brief.md MEMORY.md settings.json; do
  mkdir -p "$D18/$(dirname "$old")"
  ln -s "$SRC9/config/opinionated/$old" "$D18/$old"   # target never existed: same as removed
done
dangling18() { find "$D18" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' '; }
before18="$(dangling18)"
chmod 500 "$D18/commands"
rc18="$(run_cfg "$D18" "$T9")"
after18="$(dangling18)"
ok "an unwritable sweep root: exits non-zero" "$([ "$rc18" != 0 ] && echo yes || echo no)" yes
ok "…names each link it could not retire"    "$(grep -cE '^  fail +commands/' "$TMP/out" | tr -d ' ')" 3
# The defect verbatim: a `retire` line for a link that is still on disk. Asserted on the
# very file it printed one for before the fix, so the assertion names the lie.
ok "…claims no retirement it did not perform" "$(said 'retire commands/grill.md')" no
# The handover count must equal what actually left the disk — computed, never a literal, so
# it cannot drift with the fixture and cannot be satisfied by suppressing the note.
ok "…its count matches what it really did"   "$(said "Those $((before18 - after18)) path(s)")" yes
ok "…which is 4 of the 7, not all 7"         "$((before18 - after18))" 4
ok "…the un-retired links are still there"   "$(find "$D18/commands" -type l | wc -l | tr -d ' ')" 3
ok "…and it warns they still register"       "$(said 'still registered and still dangling')" yes
chmod 700 "$D18/commands"

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

# --------------------------------------------------------------------------- #
echo "-- …and an uninstall that could not detach says so"
# The worst measured instance of the unchecked-write defect, because of what it leaves:
# `--config --uninstall` with `commands/` and `agents/` at mode 500 printed three `rm` lines
# and 21 `retire` lines for 8 actual removals, exited 0, and left THREE LINKS STILL LIVE
# into the checkout the user had just detached from. An uninstall that reports success and
# did not detach is worse than one that refuses: nothing will prompt a second run, and the
# links keep resolving until the checkout is deleted, at which point they dangle. Both
# halves fail in this fixture — the `rm` of live links AND the sweep of dangling ones — so
# it pins that neither is reported through the other's counter.
D19="$(newdest 19)"; run_cfg "$D19" "$TPL" >/dev/null
SRC10="$(cd "$TPL" && pwd)"
for old in commands/grill.md commands/acp.md; do
  mkdir -p "$D19/$(dirname "$old")"
  ln -s "$SRC10/config/opinionated/$old" "$D19/$old"
done
ln -s "$SRC10/config/opinionated/MEMORY.md" "$D19/MEMORY.md"   # removable: top level is writable
chmod 500 "$D19/agents" "$D19/commands"
rc19="$(run_cfg "$D19" "$TPL" --uninstall)"
ok "an unwritable uninstall: exits non-zero" "$([ "$rc19" != 0 ] && echo yes || echo no)" yes
ok "…names each link it could not remove"   "$(grep -cE '^  fail +agents/' "$TMP/out" | tr -d ' ')" 3
ok "…and each one the sweep could not"      "$(grep -cE '^  fail +commands/' "$TMP/out" | tr -d ' ')" 2
# The lie, verbatim: "rm agents/code-architect.md" for a link that is still live.
ok "…prints no rm line for a link it kept"  "$(grep -cE '^  rm +agents/' "$TMP/out" | tr -d ' ')" 0
ok "…says the uninstall is incomplete"      "$(said 'uninstall is INCOMPLETE')" yes
ok "…the three links are still live"        "$(find "$D19/agents" -type l -exec test -e {} \; -print | wc -l | tr -d ' ')" 3
# What it COULD do, it still did — a failure elsewhere must not turn the whole run into a
# no-op, or the next run has more to clean up than this one did.
ok "…and the writable ones were retired"    "$(yn test -L "$D19/MEMORY.md")" no
chmod 700 "$D19/agents" "$D19/commands"

# The fixture above proves the MESSAGES but not the EXIT CODE, because its `rm` half fails
# too and either counter alone makes the run non-zero. Mutation-tested: deleting
# `config_sweep_warn || rc=1` from config_uninstall left it at 112 passed, 0 failed. That is
# the shape of every defect in this group — an assertion satisfied by a sibling — so the
# sweep's own contribution to the exit status gets a fixture where nothing else can supply
# it: the `rm` half succeeds completely, and only the sweep fails.
D20="$(newdest 20)"; run_cfg "$D20" "$TPL" >/dev/null
for old in commands/grill.md commands/acp.md; do
  mkdir -p "$D20/$(dirname "$old")"
  ln -s "$SRC10/config/opinionated/$old" "$D20/$old"
done
chmod 500 "$D20/commands"
rc20="$(run_cfg "$D20" "$TPL" --uninstall)"
ok "sweep alone failing: exits non-zero"    "$([ "$rc20" != 0 ] && echo yes || echo no)" yes
ok "…the rm half fully succeeded"           "$(grep -cE '^  rm +agents/' "$TMP/out" | tr -d ' ')" 3
ok "…so no rm failure supplied that status" "$(grep -cE '^  fail +agents/' "$TMP/out" | tr -d ' ')" 0
ok "…only the sweep did"                    "$(grep -cE '^  fail +commands/' "$TMP/out" | tr -d ' ')" 2
chmod 700 "$D20/commands"

# --------------------------------------------------------------------------- #
echo "-- …and a directory it cannot LIST is a failure, not an empty sweep"
# THE THIRD ROUTE TO THE SAME FAILURE, and the one no fixture reached: the checked `rm` and
# the quoted `find $roots` both fixed the REMOVAL half, while both `find` calls that feed
# the sweep still ended `2>/dev/null || true` — discarding the difference between "no links
# to retire" and "could not read the directory". Mode 0300 (writable, UNREADABLE — a `chmod`
# typo, or an odd umask) measured on the real in-place upgrade: exit 0, 11 `retire`, "Those
# 11 path(s) … they moved", 0 fail, 0 warn, and TEN dangling commands still registered. It
# is the worse of the two modes precisely because it is silent: at mode 500 the `rm` at
# least failed. Every directory the sweep must list is probed by name before anything is
# counted; `find`'s own status is kept as a backstop, and reports only when the probe found
# nothing, so one cause is never counted twice. BOTH HALVES ARE PINNED, by mutation on this
# one fixture: disable the probe and it stays red but nameless (1 failure, the
# "names the directory" assertion); disable the probe AND discard `find`'s status the way it
# used to be discarded, and the exit code and the warning go too (3 failures). Neither guard
# is therefore held up by the other.
D22="$(newdest 22)"; T11="$TMP/tpl-unreadable"; make_tpl "$T11"
run_cfg "$D22" "$T11" >/dev/null
SRC12="$(cd "$T11" && pwd)"
for old in commands/grill.md commands/acp.md; do
  mkdir -p "$D22/$(dirname "$old")"
  ln -s "$SRC12/config/opinionated/$old" "$D22/$old"   # target never existed: same as removed
done
ln -s "$SRC12/config/opinionated/MEMORY.md" "$D22/MEMORY.md"
chmod 0300 "$D22/commands"
rc22="$(run_cfg "$D22" "$T11")"
chmod 700 "$D22/commands"
ok "an unreadable sweep root: exits non-zero" "$([ "$rc22" != 0 ] && echo yes || echo no)" yes
ok "…names the directory it could not list"  "$(said 'commands — cannot list this directory')" yes
ok "…still retires what it COULD see"        "$(said 'retire MEMORY.md')" yes
ok "…and counts only that one"               "$(said 'Those 1 path(s)')" yes
ok "…warning that the sweep is unfinished"   "$(said 'could not finish')" yes
ok "…while the unseen links are still there" "$(find "$D22/commands" -type l | wc -l | tr -d ' ')" 2

# --------------------------------------------------------------------------- #
echo "-- …and the SOURCE side of the same question, which is the destructive one"
# THE TWIN OF THE FIXTURE ABOVE, AND THE WORSE HALF. That one is about a destination
# directory the sweep cannot read: it under-retires, loudly since the fix. This one is
# about the SOURCE tree the keep-set is derived from, and it over-retires — silently, and
# it takes the layer with it.
#
# `config_sweep` decides what to retire by asking "is this link's target still in the
# source set?". `config_entries` builds that set with `( cd … && find . -type f )` inside a
# pipeline consumed as `$(config_entries)` in a here-doc, so BOTH statuses are unreachable
# by construction. When discovery came back empty because it could not LOOK, every live
# link of ours read as dangling — `test -e` follows the link into the directory it cannot
# stat — and the sweep deleted them, printed `retire` for each, and exited 0.
#
# Measured on this fixture at the parent commit, three modes, all identical: exit 0, a
# `retire` line for each of the 5 links, ZERO links left, the three agents this layer
# still ships among them. `config/required/agents` at 0400 produced NO STDERR AT ALL.
#
# WHY THIS IS NOT A STATUS FIXTURE. `find . -type f` in a directory that is unreadable but
# executable exits 0 and prints nothing, so `pipefail`, keeping `find`'s status, or
# checking the subshell would all pass on the input that empties the layer. The guard is
# stated over two SETS — "discovery returned nothing while links into $CONFIG_SRC still
# exist" — and the tier still being present is what separates it from the legitimate
# `rm -rf config/required`, which is the control below and must still retire.
#
# THERE ARE TWO GUARDS AND NEITHER SUBSUMES THE OTHER, so both are pinned separately,
# by mutation on these fixtures, one at a time:
#   * delete the SET guard (empty discovery + live links + a tier still present) and the
#     EMPTY-BUT-PRESENT fixture below goes exit 0 / 5 retired / 0 links left — 5 failures.
#     It is the fixture that pins it, and it deliberately uses no unusual permission:
#     under an unreadable directory the probe fires too, so those fixtures cannot tell you
#     which guard held. Measured while writing this: with the set guard deleted, the three
#     unreadable modes below stay entirely GREEN — same exit code, same message, layer
#     intact — because the probe covers them. A fixture that only ever exercises a
#     permission error therefore proves nothing about this guard, which is the trap this
#     line exists to record.
#   * delete the PROBE's refusal and the partial fixture — one unreadable subdirectory
#     among two, so discovery is non-empty and the set guard is structurally blind —
#     retires the three agents this layer still ships: 3 failures, while the exit code
#     stays non-zero. That is the same silent loss under a red exit.
#   * neuter config_src_probe entirely and the refusal still holds; it just stops naming
#     the directory (3 failures).
blind_src() { # <label> <mode> <path under the template> <expect the cause named>
  local label="$1" mode="$2" rel="$3" named="$4" d t src rc old
  d="$(newdest 23)"; t="$TMP/tpl-blindsrc-$label"; rm -rf "$t"; make_tpl "$t"
  run_cfg "$d" "$t" >/dev/null            # the three agents this layer ships are now linked
  src="$(cd "$t" && pwd)"
  for old in commands/grill.md MEMORY.md; do   # …plus what the OLD layer left behind
    mkdir -p "$d/$(dirname "$old")"
    ln -s "$src/config/opinionated/$old" "$d/$old"
  done
  ok "[$label] the upgrade fixture is in place" "$(find "$d" -type l | wc -l | tr -d ' ')" 5
  chmod "$mode" "$t/$rel"
  rc="$(run_cfg "$d" "$t")"
  chmod 0700 "$t/$rel"
  ok "[$label] exits non-zero"                 "$([ "$rc" != 0 ] && echo yes || echo no)" yes
  ok "[$label] …refuses instead of retiring"   "$(said 'REFUSING to retire')" yes
  ok "[$label] …and retires NOTHING"           "$(said 'no longer shipped')" no
  # The assertion that would have caught this at the parent commit, and the only one that
  # cannot be satisfied by a message: the links are still on disk afterwards.
  ok "[$label] …so every link is still there"  "$(find "$d" -type l | wc -l | tr -d ' ')" 5
  ok "[$label] …the 3 we ship among them"      "$(find "$d/agents" -type l | wc -l | tr -d ' ')" 3
  ok "[$label] …names the source directory"    "$(said "$named")" yes
  ok "[$label] …and no success epilogue"       "$(said 'Next: restart')" no
}
# The silent one first: at the parent commit this run printed nothing on stderr whatsoever.
blind_src subdir-0400 0400 config/required/agents 'cannot list this source directory'
blind_src subdir-0000 0000 config/required/agents 'cannot list this source directory'
# The tier itself, where the `cd` is what fails rather than the `find`.
blind_src tier-0400   0400 config/required       'cannot list this source directory'

# --------------------------------------------------------------------------- #
echo "-- …and PARTIAL blindness, which the set guard structurally cannot see"
# The case the two-set statement does NOT cover, and the reason there are two guards.
# With a second readable directory under the tier, discovery comes back NON-EMPTY — one
# file, from the readable half — so "no entries while links still exist" is simply false
# and the set guard correctly stays out of the way. Meanwhile every link under the
# unreadable half still fails `test -e` and reads as retired. Today `config/required`
# holds one directory, so this shape is one `mkdir` away rather than hypothetical, and a
# guard written only over the two sets would ship a hole that opens the day a second
# directory is added. The probe's refusal is what closes it; delete that refusal and the
# three agents this layer ships are retired here with the exit code still non-zero.
D25="$(newdest 25)"; T14="$TMP/tpl-partialsrc"; make_tpl "$T14"
mkdir -p "$T14/config/required/rules"; printf 'x\n' > "$T14/config/required/rules/keep.md"
run_cfg "$D25" "$T14" >/dev/null
SRC14="$(cd "$T14" && pwd)"
mkdir -p "$D25/commands"; ln -s "$SRC14/config/opinionated/commands/grill.md" "$D25/commands/grill.md"
ok "3 agents + a second dir + one stale link" "$(find "$D25" -type l | wc -l | tr -d ' ')" 5
chmod 0000 "$T14/config/required/agents"
rc25="$(run_cfg "$D25" "$T14")"
chmod 0700 "$T14/config/required/agents"
# Proves the fixture is the partial case and not another empty one: the readable half was
# discovered, so the emptiness test below could never have fired.
ok "…discovery was NOT empty: rules/keep.md seen" "$(said 'rules/keep.md')" yes
ok "…exits non-zero"                          "$([ "$rc25" != 0 ] && echo yes || echo no)" yes
ok "…refuses on an INCOMPLETE list"            "$(said 'source list is INCOMPLETE')" yes
ok "…and retires NOTHING"                      "$(said 'no longer shipped')" no
ok "…so the 3 agents are still linked"         "$(find "$D25/agents" -type l | wc -l | tr -d ' ')" 3
ok "…and the stale link is still there too"    "$(yn test -L "$D25/commands/grill.md")" yes
ok "…and no success epilogue"                  "$(said 'Next: restart')" no

# --------------------------------------------------------------------------- #
echo "-- …and an EMPTY-but-present tier, where only the set guard can fire"
# THE FIXTURE THAT PINS THE SET GUARD, and it needs no unusual permission at all. Every
# directory is readable, so the probe finds nothing to report and its refusal cannot fire;
# discovery is empty because the tier holds no linkable file. That is the same observable
# state an unreadable tier produces, and the installer genuinely cannot tell the two
# apart — which is the argument for refusing both. Delete the set guard and this fixture
# goes exit 0 / 5 retired / 0 left, with nothing else in the suite noticing.
#
# CONTRAST IT WITH "an empty tier: exits 0" further up, which is the SAME source state and
# stays green: there are no links there. The refusal is about the pair of sets, never about
# the source alone, and these two fixtures are the two sides of that.
#
# `README.md` rather than a truly empty directory, so the fixture also proves the count is
# taken AFTER the never-linked exclusions rather than from a raw `find`.
D26="$(newdest 26)"; T15="$TMP/tpl-emptied"; make_tpl "$T15"
run_cfg "$D26" "$T15" >/dev/null
SRC15="$(cd "$T15" && pwd)"
for old in commands/grill.md MEMORY.md; do
  mkdir -p "$D26/$(dirname "$old")"
  ln -s "$SRC15/config/opinionated/$old" "$D26/$old"
done
ok "the same 5 links, nothing unreadable"    "$(find "$D26" -type l | wc -l | tr -d ' ')" 5
rm -f "$T15/config/required/agents/"*.md; printf 'x\n' > "$T15/config/required/agents/README.md"
rc26="$(run_cfg "$D26" "$T15")"
ok "an emptied but PRESENT tier: non-zero"   "$([ "$rc26" != 0 ] && echo yes || echo no)" yes
ok "…and the probe reported nothing"         "$(said 'cannot list this source directory')" no
ok "…so it is the set guard that refused"    "$(said 'discovered no files under')" yes
ok "…retiring NOTHING"                       "$(said 'no longer shipped')" no
ok "…leaving all five links in place"        "$(find "$D26" -type l | wc -l | tr -d ' ')" 5
ok "…and it says how to mean it for real"    "$(said 'remove the tier directory')" yes

# --------------------------------------------------------------------------- #
echo "-- …while a source tree that is genuinely GONE still retires, which is the control"
# THE OTHER HALF OF THE GUARD, and the reason it is stated the way it is. A human running
# `rm -rf config/required` produces the same empty source set, and there retiring every
# link IS correct — it is the AUTONOMY.md contract this installer documents: delete the
# directory, lose the capability, break nothing. A guard that refused here would be a
# different bug, so the control is asserted with the same fixture and the same five links.
D24="$(newdest 24)"; T13="$TMP/tpl-gonesrc"; make_tpl "$T13"
run_cfg "$D24" "$T13" >/dev/null
SRC13="$(cd "$T13" && pwd)"
for old in commands/grill.md MEMORY.md; do
  mkdir -p "$D24/$(dirname "$old")"
  ln -s "$SRC13/config/opinionated/$old" "$D24/$old"
done
ok "the same 5 links, the legitimate case"   "$(find "$D24" -type l | wc -l | tr -d ' ')" 5
rm -rf "$T13/config/required"; mkdir -p "$T13/config"
rc24="$(run_cfg "$D24" "$T13")"
ok "a REMOVED tier: exits 0"                 "$rc24" 0
ok "…retires every one of them"              "$(find "$D24" -type l | wc -l | tr -d ' ')" 0
ok "…and says that is what it did"           "$(said 'no longer shipped')" yes
ok "…refusing nothing"                       "$(said 'REFUSING')" no
ok "…and nothing is reported as an error"    "$(said 'error')" no

# --------------------------------------------------------------------------- #
echo "-- …and a root ANOTHER installer moved aside is swept too"
# NO UNUSUAL PERMISSIONS, AND IT IS THE ORDER THIS REPO RECOMMENDS. ai-setup links each
# top-level entry as a whole unit, moving the real directory to `<root>.bak.<epoch>` first.
# So on the normal machine `$CONFIG_DEST/commands` becomes a SYMLINK — which the roots loop
# skips, correctly, since we never write through one — and the links this layer must retire
# are now inside a `.bak.<epoch>` DIRECTORY that the top-level `-maxdepth 1` scan does not
# see. Measured on the real upgrade in that order: `--config` retired 2 of 21 and reported
# "Those 2 path(s)", leaving 19 dangling and unmentioned; `--config --uninstall` exited 0
# with three links still LIVE into the checkout the user had just detached from.
D21="$(newdest 21)"; T10="$TMP/tpl-movedaside"; make_tpl "$T10"
run_cfg "$D21" "$T10" >/dev/null
SRC11="$(cd "$T10" && pwd)"
mkdir -p "$D21/commands"
for old in commands/grill.md commands/acp.md; do
  ln -s "$SRC11/config/opinionated/$old" "$D21/$old"
done
mkdir -p "$TMP/asetup2/commands"
while IFS= read -r a; do
  [ -n "$a" ] || continue
  printf 'ai-setup copy of %s\n' "$a" > "$TMP/asetup2/agents/$a"
done <<AGENTS2
$(mkdir -p "$TMP/asetup2/agents"; cd "$T10/config/required/agents" && ls)
AGENTS2
# Exactly what ai-setup's link() does: mv the real root aside, then link the root.
mv "$D21/commands" "$D21/commands.bak.1700000001"; ln -s "$TMP/asetup2/commands" "$D21/commands"
mv "$D21/agents"   "$D21/agents.bak.1700000002";   ln -s "$TMP/asetup2/agents"   "$D21/agents"
rc21="$(run_cfg "$D21" "$T10")"
ok "after another installer took the roots: exits 0" "$rc21" 0
ok "…the dangling links it moved aside are gone" "$(find "$D21/commands.bak.1700000001" -type l | wc -l | tr -d ' ')" 0
ok "…named with the directory they are in"   "$(said 'retire commands.bak.1700000001/grill.md')" yes
ok "…so the handover count is 2, not 0"      "$(said 'Those 2 path(s)')" yes
ok "…and our three are reported as provided" "$(said 'provided by another config layer')" yes
# The LIVE links of ours inside the moved-aside root are not an install's business — they
# point at files this layer still ships. They are very much an UNINSTALL's.
ourslive() { # <dir> <template root> → how many live links there point into that template
  local n=0 x
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    case "$(readlink "$x")" in "$2"/config/*) n=$((n+1)) ;; esac
  done <<INNER
$(find "$1" -type l -exec test -e {} \; -print 2>/dev/null)
INNER
  printf '%s' "$n"
}
ok "…live links of ours survive the install"  "$(ourslive "$D21/agents.bak.1700000002" "$SRC11")" 3
rc21u="$(run_cfg "$D21" "$T10" --uninstall)"
ok "--uninstall from that state exits 0"      "$rc21u" 0
ok "…and NOTHING still points into the checkout" "$(ourslive "$D21" "$SRC11")" 0
ok "…each detached link named"                 "$(grep -cE '^  detach ' "$TMP/out" | tr -d ' ')" 3
# One link, one line: the entries loop and the sweep must not both claim the same path.
D21b="$(newdest 29)"; run_cfg "$D21b" "$TPL" >/dev/null
run_cfg "$D21b" "$TPL" --uninstall >/dev/null
ok "a plain uninstall reports each link once"  "$(grep -cE '^  (rm|detach) ' "$TMP/out" | tr -d ' ')" 3
ok "…through the entries loop, not the sweep"  "$(grep -cE '^  detach ' "$TMP/out" | tr -d ' ')" 0

# --------------------------------------------------------------------------- #
echo "-- …and the sweep RECURSES, which one shipped path was ever deep enough to prove"
# `-maxdepth 1` on the roots `find` keeps this suite green: the only real path deeper than
# one level under a root is `skills/test-locators/SKILL.md`, and nothing had a fixture for
# it. A skill is a directory of files by construction, so this is the shape of every future
# one.
D23="$(newdest 23)"; T12="$TMP/tpl-deep"; make_tpl "$T12"
run_cfg "$D23" "$T12" >/dev/null
SRC13="$(cd "$T12" && pwd)"
mkdir -p "$D23/skills/test-locators"
ln -s "$SRC13/config/opinionated/skills/test-locators/SKILL.md" "$D23/skills/test-locators/SKILL.md"
ok "a dangling link two levels down: exits 0" "$(run_cfg "$D23" "$T12")" 0
ok "…is retired as well"                      "$(yn test -L "$D23/skills/test-locators/SKILL.md")" no
ok "…and it said so"                          "$(said 'retire skills/test-locators/SKILL.md')" yes

# --------------------------------------------------------------------------- #
echo "-- …and the dead-backup rm is checked like every other write"
# Same rule, third caller. The fixture ISOLATES it: `agents/` stays writable so the link
# half succeeds completely, and the only thing that can fail is the `rm` of a dead backup
# under `commands/` — otherwise the non-zero exit would be supplied by a sibling, which is
# the defect shape this whole section exists to prevent.
D24="$(newdest 24)"; T13="$TMP/tpl-deadbak"; make_tpl "$T13"
run_cfg "$D24" "$T13" >/dev/null
SRC14="$(cd "$T13" && pwd)"
mkdir -p "$D24/commands"
# A dead backup is `.bak.<digits>` + a dangling symlink + the entry it backs up existing
# again as a link of ours. All three, or dead_backup() declines — see its comment.
# The backup's target is the checkout's OLD path — that is the only way this debris is
# created (one `mv` of the checkout, then one repair install) and the reason the sweep's
# first branch cannot see it: `ours` tests the target against the template's CURRENT
# location, which a moved link fails by construction.
ln -s "$SRC14/config/required/agents/code-architect.md" "$D24/commands/grill.md"
ln -s "$TMP/moved-away/config/opinionated/commands/grill.md" "$D24/commands/grill.md.bak.1700000003"
chmod 500 "$D24/commands"
rc24="$(run_cfg "$D24" "$T13")"
chmod 700 "$D24/commands"
ok "an unremovable dead backup: exits non-zero" "$([ "$rc24" != 0 ] && echo yes || echo no)" yes
ok "…says what it could not remove"            "$(said 'cannot remove this dead backup')" yes
ok "…and it is still on disk"                  "$(yn test -L "$D24/commands/grill.md.bak.1700000003")" yes
ok "…no link write supplied that status"       "$(grep -cE '^  fail +agents/' "$TMP/out" | tr -d ' ')" 0
rc24b="$(run_cfg "$D24" "$T13")"
ok "with the directory writable: exits 0"      "$rc24b" 0
ok "…the dead backup is swept"                 "$(yn test -L "$D24/commands/grill.md.bak.1700000003")" no
ok "…and it printed where it had pointed"      "$(said 'dead backup of a relinked file')" yes

# --------------------------------------------------------------------------- #
echo "-- …and 'ours' is decided by TARGET, not by a prefix that looks like ours"
# `case "$tgt" in "$CONFIG_SRC"/*)` — the trailing slash is the whole guard, in config_ours
# and in the sweep's first branch. What it excludes is a path that EXTENDS `config`'s name
# inside this very checkout: `config.bak/`, which is exactly what a human makes by hand
# before a migration like this one. Without the slash such a link is "ours", so the sweep
# retires it and an uninstall removes it — deleting somebody's own backup of the layer they
# were about to lose.
D25="$(newdest 25)"; run_cfg "$D25" "$TPL" >/dev/null
# Spelled the way the INSTALLER spells its own root (`cd && pwd`), which normalises away the
# `//` that $TMPDIR carries — otherwise this link is one no real install could produce and
# the prefix test is never reached at all. Same trap as the handover fixture above.
SRCTPL="$(cd "$TPL" && pwd)"
ln -s "$SRCTPL/config.bak/required/agents/code-architect.md" "$D25/agents/lookalike.md"
ok "a dangling link into config.bak/: exits 0" "$(run_cfg "$D25" "$TPL")" 0
ok "…is NOT retired"                          "$(yn test -L "$D25/agents/lookalike.md")" yes
run_cfg "$D25" "$TPL" --uninstall >/dev/null
ok "…nor removed by an uninstall"             "$(yn test -L "$D25/agents/lookalike.md")" yes
ok "…while ours in the same directory went"   "$(yn test -L "$D25/agents/code-architect.md")" no

# --------------------------------------------------------------------------- #
echo "-- …and 'provided' means a FILE, which is what the consumer probes for"
# `[ -f ]`, not `[ -e ]`: `-e` is true for a DIRECTORY, so a directory named
# `code-architect.md` in the provider's tree would be reported as provided — this run writes
# nothing, exits 0, and `test -f ~/.claude/agents/code-architect.md` in
# `plugin/agents/qa-reviewer.md` still fails, silently, in a session. That line is
# the entire content of its own commit and nothing covered it.
D26="$(newdest 26)"; mkdir -p "$TMP/asetup3/agents/code-architect.md"
for a in deep-bug-scan.md plan-architect.md; do printf 'ai-setup copy\n' > "$TMP/asetup3/agents/$a"; done
ln -s "$TMP/asetup3/agents" "$D26/agents"
rc26="$(run_cfg "$D26" "$TPL")"
ok "a DIRECTORY in the provider's slot: refused" "$([ "$rc26" != 0 ] && echo yes || echo no)" yes
ok "…not counted as provided"                 "$(grep -c 'agents/code-architect.md (provided by' "$TMP/out" | tr -d ' ')" 0
ok "…while the two real files are"            "$(grep -c '(provided by' "$TMP/out" | tr -d ' ')" 2
ok "…and nothing was written into that tree"  "$(find "$TMP/asetup3/agents/code-architect.md" -mindepth 1 | wc -l | tr -d ' ')" 0
# The remediation it prints must not tell the user to break the provider that owns the dir:
# ai-setup links these roots as units BY DESIGN, so a bare `mv` there deactivates everything
# it ships and its next run moves the replacement aside again — the two installers ping-pong.
ok "…it points at the provider's installer first" "$(said 'run ITS')" yes
ok "…and offers the mv only for an unowned link"  "$(said 'belongs to no installer')" yes

# --------------------------------------------------------------------------- #
echo "-- …and a config dir that cannot be created is a refusal"
# The last unchecked write in the link half. Its failure was reported only by the per-entry
# `mkdir -p "$dstdir"` below it, and only because every shipped entry happens to live in a
# subdirectory — an incidental guarantee, not a stated one.
NOPARENT="$TMP/noparent"; mkdir -p "$NOPARENT"; chmod 500 "$NOPARENT"
rc27="$(run_cfg "$NOPARENT/cfg" "$TPL")"
chmod 700 "$NOPARENT"
ok "an uncreatable config dir: exits non-zero" "$([ "$rc27" != 0 ] && echo yes || echo no)" yes
ok "…and says nothing was written"             "$(said 'Nothing was written')" yes
ok "…having created no config dir at all"      "$(yn test -d "$NOPARENT/cfg")" no

# --------------------------------------------------------------------------- #
echo "-- …and a settings.json that reappears under config/ is still not linked"
# The exclusion in `config_entries` is not decoration: `~/.claude/settings.json` is the one
# file in the config dir that can already hold permissions a human tuned by hand, it belongs
# to ai-setup, and this layer must not link, back up, edit or mention it. A re-forked copy
# appearing under `config/` is how it would come back — silently linked on the next run.
T14="$TMP/tpl-sjs"; make_tpl "$T14"
printf '{"permissions":{"deny":["Read(**/.env)"]}}\n' > "$T14/config/required/settings.json"
D28="$(newdest 28)"
ok "a settings.json under config/: exits 0"   "$(run_cfg "$D28" "$T14")" 0
ok "…is NOT linked"                           "$(yn test -e "$D28/settings.json")" no
ok "…and is not even mentioned"               "$(said 'settings.json')" no
ok "…while the agents still are linked"       "$(find "$D28/agents" -type l | wc -l | tr -d ' ')" 3

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
