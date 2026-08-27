#!/usr/bin/env bash
#
# installer-worktree-guard.test.sh — `install.sh` may not run from a git worktree.
#
# WHY. It derives its source from `dirname $0` and then creates symlinks pointing AT that
# path — an instance's whole machinery set. A linked worktree is temporary by design —
# ExitWorktree or `git worktree remove` deletes it — so every symlink made from one dangles
# the moment it goes. Nothing fails at install time; the commands and hooks simply
# disappear later, which is the worst shape a failure can take.
#
# It is not hypothetical: this project's convention is to work on a branch in a worktree,
# so a checkout of the installer is routinely one `cd` away from the wrong answer. It was
# recorded as a structural hazard during a plan review and went unfixed until then.
#
# The load-bearing assertions are the two directions together. "It refuses in a worktree"
# alone would pass a script that refuses everywhere.
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
# instance or touches the user's own workspace.
make_template() { # <dir>
  local d="$1"
  mkdir -p "$d/seed" "$d/symlink/scripts"
  cp "$REPO/install.sh" "$d/install.sh"
  printf '{}\n' > "$d/seed/instance.config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/symlink/scripts/s.sh"
  printf 'x\n' > "$d/symlink/SCHEMA.md"
}

M="$TMP/main"; make_template "$M"
( cd "$M" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
git -C "$M" worktree add -q "$TMP/linked" -b wt >/dev/null 2>&1
L="$TMP/linked"

run() { local src="$1" target="$2"; bash "$src/install.sh" "$target" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# --- the main working tree must still work (the non-vacuity half) -----------
i="$TMP/inst1"; mkdir -p "$i"
ok "installer runs from the main tree"           "$(run "$M" "$i")" 0
ok "…and it actually stamped the instance"       "$([ -e "$i/instance.config.json" ] && echo yes || echo no)" yes
ok "…and linked the machinery"                   "$([ -L "$i/SCHEMA.md" ] && echo yes || echo no)" yes

# --- a linked worktree must be refused, exit 2, before any write -----------
i2="$TMP/inst2"; mkdir -p "$i2"
rc="$(run "$L" "$i2")"
ok "installer refuses from a worktree"           "$rc" 2
ok "…says why"                                   "$(grep -qi 'refusing to install from a git worktree' "$TMP/out" && echo yes || echo no)" yes
# Compare nothing derived: mktemp hands back /var/... while git reports /private/var/...
# on macOS, so an unresolved path grep fails on a correct message.
ok "…tells you how to find the main tree"        "$(grep -q 'worktree list' "$TMP/out" && echo yes || echo no)" yes
# It must NOT print a computed path: every derivation is wrong once the git metadata lives
# apart from the working tree, and a confidently wrong path to paste is worse than none.
# Asserted so nobody "improves" the message by deriving one.
ok "…and does not guess a checkout path"         "$(grep -qE '^Run it from.*/(install|ai-bridge)' "$TMP/out" && echo no || echo yes)" yes
ok "…and stamped NOTHING"                        "$(find "$i2" -mindepth 1 | wc -l | tr -d ' ')" 0

# --- a plain `git init` repo is a MAIN tree, so the guard must not fire there.
# Every fixture in this suite is built that way; if the guard misread them, the whole
# harness would break rather than this one assertion, so assert it explicitly.
P="$TMP/plain"; make_template "$P"
( cd "$P" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
i3="$TMP/inst3"; mkdir -p "$i3"
ok "a plain git repo is not treated as a worktree" "$(run "$P" "$i3")" 0

# --- and outside git entirely: no repo, no guard, still installs -----------
N="$TMP/nogit"; make_template "$N"
i4="$TMP/inst4"; mkdir -p "$i4"
rc="$(run "$N" "$i4")"
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

i5="$TMP/inst5"; mkdir -p "$i5"
ok "separate metadata, main tree: it stamps"     "$(run "$S/main" "$i5")" 0
i6="$TMP/inst6"; mkdir -p "$i6"
ok "separate metadata, worktree: it refuses"     "$(run "$S/wt" "$i6")" 2
ok "…and stamped nothing"                        "$(find "$i6" -mindepth 1 | wc -l | tr -d ' ')" 0
ok "…and still names no derived path"            "$(grep -qE '^Run it from.*/(install|ai-bridge)' "$TMP/out" && echo no || echo yes)" yes
git -C "$S/main" worktree remove --force "$S/wt" 2>/dev/null

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
