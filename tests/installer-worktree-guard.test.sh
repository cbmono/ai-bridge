#!/usr/bin/env bash
#
# installer-worktree-guard.test.sh — the config layer may not be linked from a git
# worktree, and a BUNDLE STAMP no longer cares.
#
# WHY THE GUARD EXISTS. `init-bundle.sh --config` derives its source from `dirname $0` and
# then creates symlinks in ${CLAUDE_CONFIG_DIR:-~/.claude} pointing AT that path. A linked
# worktree is temporary by design — ExitWorktree or `git worktree remove` deletes it — so
# every symlink made from one dangles the moment it goes. Nothing fails at link time; the
# agents simply disappear later, which is the worst shape a failure can take.
#
# WHY IT NARROWED (ai-bridge-v2/task-013). The guard used to cover BOTH halves, because a
# bundle stamp also wrote absolute symlinks into the source checkout — 37 of them, an
# instance's whole machinery set. A bundle carries no machinery now: `/ai-bridge:init`
# copies seed content and links only `repos/`, which points at reposRoot and never at this
# checkout. So for that half the hazard is gone, and with it the refusal — which had a
# cost of its own, since every role agent works in a worktree and every fixture in this
# suite had to copy the template out of the checkout to dodge it.
#
# THE LOAD-BEARING ASSERTIONS ARE THE TWO DIRECTIONS TOGETHER. "It refuses in a worktree"
# alone would pass a script that refuses everywhere; "a stamp is allowed" alone would pass
# one that never refuses at all. Both halves, from the SAME worktree, in this file.
#
# HISTORY. This file is the ai-bridge half of `ai-setup`'s test of the same name, ported
# when ai-bridge became its own repo. The parent repo keeps the half that covers its own
# user-wide installer; neither guard is left untested.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtguard.XXXXXX")" || {
  echo "installer-worktree-guard.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'git -C "$TMP/main" worktree remove --force "$TMP/linked" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-54s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-54s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# A fixture template carrying a copy of the installer, so the test never stamps a real
# bundle, never writes into the user's own ~/.claude, and never touches this checkout.
# `VERSION` is what the installer verifies its template-root derivation against, so a
# fixture without one is not a template at all.
make_template() { # <dir>
  local d="$1"
  mkdir -p "$d/plugin/seed" "$d/plugin/scripts" "$d/config/required/agents" "$d/.claude-plugin"
  cp "$REPO/VERSION" "$d/VERSION"
  cp "$REPO/VERSION" "$d/plugin/VERSION"
  # The marketplace manifest is what tells init-bundle.sh there is a CHECKOUT around the
  # plugin — and the worktree guard under test only has a checkout to refuse when there is.
  printf '{ "name": "ai-bridge", "plugins": [] }\n' > "$d/.claude-plugin/marketplace.json"
  cp "$REPO/plugin/scripts/init-bundle.sh" "$d/plugin/scripts/init-bundle.sh"
  printf '{}\n' > "$d/plugin/seed/instance.config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/plugin/scripts/s.sh"
  printf 'x\n' > "$d/plugin/seed/SCHEMA.md"
  printf '# a probed agent\n' > "$d/config/required/agents/plan-architect.md"
}

M="$TMP/main"; make_template "$M"
( cd "$M" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
git -C "$M" worktree add -q "$TMP/linked" -b wt >/dev/null 2>&1
L="$TMP/linked"

newdest() { local d="$TMP/dest$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
run_cfg()   { local src="$1" dest="$2"
              CLAUDE_CONFIG_DIR="$dest" bash "$src/plugin/scripts/init-bundle.sh" --config >"$TMP/out" 2>&1
              printf '%s' "$?"; }
run_stamp() { local src="$1" target="$2"
              bash "$src/plugin/scripts/init-bundle.sh" "$target" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# --- the main working tree must still work (the non-vacuity half) -----------
d1="$(newdest 1)"
ok "--config runs from the main tree"            "$(run_cfg "$M" "$d1")" 0
ok "…and it actually linked something"           "$([ -L "$d1/agents/plan-architect.md" ] && echo yes || echo no)" yes

# --- a linked worktree must be refused, exit 2, before any write -----------
d2="$(newdest 2)"
rc="$(run_cfg "$L" "$d2")"
ok "--config refuses from a worktree"            "$rc" 2
ok "…says why"                                   "$(grep -qi 'refusing to link the config layer from a git worktree' "$TMP/out" && echo yes || echo no)" yes
# Compare nothing derived: mktemp hands back /var/... while git reports /private/var/...
# on macOS, so an unresolved path grep fails on a correct message.
ok "…tells you how to find the main tree"        "$(grep -q 'worktree list' "$TMP/out" && echo yes || echo no)" yes
# It must NOT print a computed path: every derivation is wrong once the git metadata lives
# apart from the working tree, and a confidently wrong path to paste is worse than none.
# Asserted so nobody "improves" the message by deriving one.
ok "…and does not guess a checkout path"         "$(grep -qE '^Run it from.*/(install|ai-bridge)' "$TMP/out" && echo no || echo yes)" yes
ok "…and linked NOTHING"                         "$(find "$d2" -mindepth 1 | wc -l | tr -d ' ')" 0

# --- THE OTHER HALF, FROM THE SAME WORKTREE: a bundle stamp is allowed ------
# This is the change task-013 made, asserted where the refusal it replaced lives, so the
# two can never drift into agreeing.
i2="$TMP/inst-wt"
ok "a bundle stamp from that same worktree runs" "$(run_stamp "$L" "$i2")" 0
ok "…and it stamped"                             "$([ -e "$i2/instance.config.json" ] && echo yes || echo no)" yes
ok "…as real files, with no symlink at all"      "$([ -z "$(find "$i2" -type l 2>/dev/null)" ] && echo yes || echo no)" yes
ok "…SCHEMA.md included"                         "$([ -f "$i2/SCHEMA.md" ] && [ ! -L "$i2/SCHEMA.md" ] && echo yes || echo no)" yes

# --- a plain `git init` repo is a MAIN tree, so the guard must not fire there.
# Every fixture in this suite is built that way; if the guard misread them, the whole
# harness would break rather than this one assertion, so assert it explicitly.
P="$TMP/plain"; make_template "$P"
( cd "$P" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
ok "a plain git repo is not treated as a worktree" "$(run_cfg "$P" "$(newdest 3)")" 0

# --- and outside git entirely: no repo, no guard, still links -----------
N="$TMP/nogit"; make_template "$N"
rc="$(run_cfg "$N" "$(newdest 4)")"
ok "outside a git repo it does not refuse"       "$([ "$rc" -ne 2 ] && echo yes || echo no)" yes

# --- separate git metadata: the case the first version got wrong -----------
# With `git init --separate-git-dir`, .git is a FILE pointing elsewhere. In the main tree
# --git-dir and --git-common-dir still agree, so the guard must not fire; from a linked
# worktree they differ, so it must. And the message must not name a path, because every
# way of deriving one is wrong in this layout.
S="$TMP/sep"; SG="$TMP/sepgit"
mkdir -p "$SG"; make_template "$S/main"
( cd "$S/main" && git init -q --separate-git-dir="$SG/real.git" . && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm init )
git -C "$S/main" worktree add -q "$S/wt" -b sepwt >/dev/null 2>&1

ok "separate metadata, main tree: it links"      "$(run_cfg "$S/main" "$(newdest 5)")" 0
d6="$(newdest 6)"
ok "separate metadata, worktree: it refuses"     "$(run_cfg "$S/wt" "$d6")" 2
ok "…and linked nothing"                         "$(find "$d6" -mindepth 1 | wc -l | tr -d ' ')" 0
ok "…and still names no derived path"            "$(grep -qE '^Run it from.*/(install|ai-bridge)' "$TMP/out" && echo no || echo yes)" yes
git -C "$S/main" worktree remove --force "$S/wt" 2>/dev/null

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
