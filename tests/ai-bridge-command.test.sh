#!/usr/bin/env bash
#
# ai-bridge-command.test.sh — `/ai-bridge`: one banner, one list of checks, and two
# non-actions that are the reason the command exists.
#
# THE TWO PROPERTIES A REVIEWER SHOULD BE ABLE TO REFUSE THE CHANGE ON, and they are both
# assertions about something NOT happening, which is the hardest kind to trust to review:
#
#   1. `fix` never writes, reverts or stages `instance.config.json` /
#      `instance.config.local.json`. On 2026-08-30 an instance carried an uncommitted
#      `maxPrLoc: 2000 -> 500` that was a deliberate decision by its owner minutes earlier
#      and indistinguishable from drift to anything reading only the file. §4 runs `fix`
#      against exactly that state and asserts both files come out byte-identical, with the
#      index and the working tree untouched.
#
#   2. `fix` never removes, clears or rewrites `.tick-lock` or `.tick-lock.claim`, not even
#      one it judges stale. `tick-lock.sh release` is the human's override, and clearing a
#      lock on a staleness threshold re-opens the double-dispatch that ran two ticks
#      concurrently for 34 minutes on 2026-08-29 — a long tick is not a dead one. §5 plants
#      a lock two hours old, confirms the machinery itself calls it STALE, runs `fix`, and
#      asserts both files survive byte-identical.
#
# BEHAVIOUR FIRST, TEXT SECOND. Both are asserted by running the shipped script against a
# real fixture and hashing the files, not by grepping the source for an `rm`. The static
# assertions in §6 are a second, weaker net for the same class — they catch a fixer added
# for the wrong tier before it can ever run — and they are stated as what they are.
#
# THE DRIFT ASSERTION (§3) IS THE OTHER HALF OF THE DESIGN. `check` and `fix` must read ONE
# list. A harness that only checked "fix repairs the idempotent ones" would pass a build
# where `fix` carried its own five-row copy of a seven-row list, which is the silent gap the
# single list exists to prevent. So the list is read out of the script once (`--list`) and
# both forms are asserted to cover exactly its rows — and the script's own refusal to run
# with a rogue fixer is provoked with a planted one, because a guard that is never seen to
# fire is indistinguishable from a comment.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
SH="$TPL/symlink/scripts/ai-bridge.sh"
BANNER="$TPL/symlink/.claude/hooks/session-banner.sh"
CMD="$TPL/symlink/.claude/commands/ai-bridge.md"
[ -f "$SH" ] || { echo "ai-bridge-command.test: missing $SH" >&2; exit 2; }

# An explicit template, because a bare `mktemp -d` silently ignores a bogus TMPDIR on macOS
# and lands in a real /var path — which is how a broken guard here would go unnoticed.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ai-bridge-command.XXXXXX")" || {
  echo "ai-bridge-command.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
case "$TMP" in /*) ;; *) echo "ai-bridge-command.test: mktemp returned a relative path" >&2; exit 2 ;; esac
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
# Every git call names its repo with `-C` and strips the repo-redirecting GIT_* variables:
# an ambient GIT_DIR (exported inside every git hook, and by `git rebase -x`) would
# otherwise send a fixture's commits into the repo under test. Identity, signing and hooks
# are pinned per invocation so a machine with none configured still runs this.
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

sha() { # <file> — a content fingerprint that is the same on macOS and Linux
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1" | awk '{print $1}'
  else sha256sum -- "$1" | awk '{print $1}'; fi
}

# mkinstance <dir> — a git-tracked instance with the two files the banner's own gate wants.
mkinstance() {
  mkdir -p "$1/.claude/agents" "$1/scripts"
  printf '{\n  "org": "example-org",\n  "maxPrLoc": 2000,\n  "maxAgentsInFlight": 8\n}\n' > "$1/instance.config.json"
  printf 'stub\n' > "$1/SCHEMA.md"
  GIT -C "$1" init -q 2>/dev/null || GIT init -q "$1"
  GIT -C "$1" add -A
  GIT -C "$1" commit -qm "instance"
}

# =======================================================================================
echo "== 1. the bare form INVOKES the banner — it does not reproduce it =="
# =======================================================================================
# The whole point of this form is that a long session scrolls the banner out of view. If
# the two ever print differently the form is wrong, so the assertion is BYTE-IDENTICAL
# output, not "it prints a banner". A header, a blank line or a "reprinting…" notice would
# each fail here, which is exactly what should happen.
INST1="$TMP/inst1"; mkinstance "$INST1"
a="$(CLAUDE_PROJECT_DIR="$INST1" bash "$SH" 2>&1)"; arc=$?
b="$(CLAUDE_PROJECT_DIR="$INST1" bash "$BANNER" 2>&1)"; brc=$?
ok "bare /ai-bridge output is byte-identical to the hook's" "$([ "$a" = "$b" ] && echo yes || echo no)" yes
ok "…and so is its exit status"                            "$arc" "$brc"
ok "…and it is not empty (the comparison is not vacuous)"   "$([ -n "$a" ] && echo yes || echo no)" yes
# `banner` spelled out, and an unknown flag, both reach the same hook rather than being
# re-parsed here: the banner owns its own options.
c="$(CLAUDE_PROJECT_DIR="$INST1" bash "$SH" banner 2>&1)"
ok "the explicit \`banner\` form agrees too"                "$([ "$c" = "$b" ] && echo yes || echo no)" yes
d="$(CLAUDE_PROJECT_DIR="$INST1" bash "$SH" --color=never 2>&1)"
e="$(CLAUDE_PROJECT_DIR="$INST1" bash "$BANNER" --color=never 2>&1)"
ok "a flag is passed through to the hook, not re-parsed"    "$([ "$d" = "$e" ] && echo yes || echo no)" yes
# And it does not duplicate the banner's own text anywhere in the script. `AI-Bridge` is
# the identity line's literal; a copy of it here would be the start of a second banner.
ok "the script contains no copy of the banner's identity line" \
  "$(grep -c '^[^#]*AI-Bridge' "$SH" | tr -d ' ')" 0

# =======================================================================================
echo "== 2. every line of \`check\` is a FACT, and empty output is one of the answers =="
# =======================================================================================
# A rules recital was the explicitly rejected shape for this command: the rules are already
# loaded, and none of the failures this was written from were caused by a rule not being
# loaded. So the two phrases that were named as forbidden are asserted absent from
# everything this feature ships, and the checks are asserted to report their EMPTY case
# rather than falling silent.
OUT="$(bash "$SH" check --instance "$INST1" --template "$TPL" 2>&1)"; crc=$?
ok "check exits 0 on a healthy read"                       "$crc" 0
for phrase in "always use the pm-loop" "always defer to subagents"; do
  ok "no '$phrase' line in the script"  "$(grep -ci "$phrase" "$SH" | tr -d ' ')" 0
  ok "…nor in the command file"         "$(grep -ci "$phrase" "$CMD" | tr -d ' ')" 0
done
# Every row in the list produced a line, including the ones with nothing wrong. "Empty
# output is a valid, reported answer" is the criterion; silence is the failure.
n_rows="$(bash "$SH" check --list | grep -c .)"
n_lines="$(printf '%s\n' "$OUT" | grep -cE '^(⚠|✓)')"
ok "every row reported a verdict line"                     "$([ "$n_lines" -ge "$n_rows" ] && echo yes || echo no)" yes
ok "…including the 'nothing to stamp' one"                 "$(printf '%s\n' "$OUT" | grep -c 'nothing to stamp' | tr -d ' ')" 0
# INST1 is not stamped at all, so the unstamped check must FIRE — the other direction.
ok "an unstamped instance is reported as such"             "$(printf '%s\n' "$OUT" | grep -c 'are NOT linked in this instance' | tr -d ' ')" 1
ok "…with the stamp command, which is the repair"          "$(printf '%s\n' "$OUT" | grep -c 'install.sh' | tr -d ' ')" 1

# The literal post-merge form, and its EMPTY answer. `git diff --name-status <old>..<new>
# -- symlink/ | grep '^A'` is what a human runs after a merge; `--since` runs exactly that,
# and "this range added nothing" is a reported answer, not silence.
RTPL="$TMP/rangetpl"
mkdir -p "$RTPL/symlink/scripts"
printf 'old\n' > "$RTPL/symlink/scripts/one.sh"
GIT -C "$RTPL" init -q 2>/dev/null || GIT init -q "$RTPL"
GIT -C "$RTPL" add -A; GIT -C "$RTPL" commit -qm base
base="$(GIT -C "$RTPL" rev-parse HEAD)"
printf 'edited\n' > "$RTPL/symlink/scripts/one.sh"
GIT -C "$RTPL" commit -qam "edit an already-linked file"
edited="$(GIT -C "$RTPL" rev-parse HEAD)"
S1="$(bash "$SH" check --instance "$INST1" --template "$RTPL" --since "$base" 2>&1)"
ok "--since over an edit-only range REPORTS that it added nothing" \
  "$(printf '%s\n' "$S1" | grep -c 'added no symlink/ files' | tr -d ' ')" 1
printf 'brand new\n' > "$RTPL/symlink/scripts/two.sh"
GIT -C "$RTPL" add -A; GIT -C "$RTPL" commit -qm "add a new file"
S2="$(bash "$SH" check --instance "$INST1" --template "$edited" 2>/dev/null; \
      bash "$SH" check --instance "$INST1" --template "$RTPL" --since "$base" 2>&1)"
ok "…and names the added file when the range has one" \
  "$(printf '%s\n' "$S2" | grep -c 'symlink/scripts/two.sh' | tr -d ' ')" 1
ok "…while the edited file is NOT reported as added (that is the whole distinction)" \
  "$(printf '%s\n' "$S2" | grep -c '^      A.*one\.sh' | tr -d ' ')" 0

# =======================================================================================
echo "== 3. ONE list: check and fix cannot drift apart =="
# =======================================================================================
# Two lists is the design risk the feature was written against — the checker knows about
# seven things, the fixer about five, and the gap is silent. The list is read out of the
# script itself, so this cannot be satisfied by a harness that carries its own copy.
LIST="$(bash "$SH" check --list)"
ids="$(printf '%s\n' "$LIST" | awk -F'\t' '{print $1}')"
ok "the list is non-empty"                                 "$([ -n "$ids" ] && echo yes || echo no)" yes
ok "every row declares one of the three tiers" \
  "$(printf '%s\n' "$LIST" | awk -F'\t' '$2!="idempotent" && $2!="ambiguous" && $2!="human"' | grep -c . | tr -d ' ')" 0
ok "…and every row declares whether it may speak on the banner path" \
  "$(printf '%s\n' "$LIST" | awk -F'\t' '$3!="yes" && $3!="no"' | grep -c . | tr -d ' ')" 0

FIXOUT="$(bash "$SH" fix --instance "$INST1" --template "$TPL" 2>&1)"
missing_fix=""
for id in $ids; do
  printf '%s\n' "$FIXOUT" | grep -q -- "── $id \[" || missing_fix="${missing_fix:+$missing_fix }$id"
done
ok "fix walked EVERY row of the list"                      "$missing_fix" ""
# And the reverse: fix must not know about a row the list does not carry. Its section
# headers are counted against the list, so an extra hand-rolled branch would show up here.
ok "…and no row fix printed is absent from the list" \
  "$(printf '%s\n' "$FIXOUT" | sed -n 's/^── \([a-z-]*\) \[.*/\1/p' | sort -u \
     | comm -23 - <(printf '%s\n' "$ids" | sort -u) | grep -c . | tr -d ' ')" 0
# The tier fix printed for each row is the tier the LIST declares, not a second opinion.
mismatch=0
while IFS="$(printf '\t')" read -r id tier _; do
  [ -n "$id" ] || continue
  printf '%s\n' "$FIXOUT" | grep -q -- "── $id \[$tier\]" || mismatch=$((mismatch+1))
done <<EOF
$LIST
EOF
ok "…and dispatched on the tier the row declares"          "$mismatch" 0

# =======================================================================================
echo "== 4. SHIP-BLOCKER: fix never touches a config file =="
# =======================================================================================
# Uncommitted config is a QUESTION, never a defect. The fixture is the measured case: a
# tracked config edited but not committed, plus a per-machine file beside it. A `fix` that
# reverted, staged or rewrote either would have destroyed a decision made minutes earlier.
INST2="$TMP/inst2"; mkinstance "$INST2"
python3 - "$INST2" <<'PY' 2>/dev/null || sed -i.bak 's/"maxPrLoc": 2000/"maxPrLoc": 500/' "$INST2/instance.config.json"
import json, os, sys
p = os.path.join(sys.argv[1], "instance.config.json")
cfg = json.load(open(p)); cfg["maxPrLoc"] = 500
json.dump(cfg, open(p, "w"), indent=2)
PY
rm -f "$INST2/instance.config.json.bak"
printf '{\n  "ownerGithubUser": "example-user-007"\n}\n' > "$INST2/instance.config.local.json"

cfg_before="$(sha "$INST2/instance.config.json")"
loc_before="$(sha "$INST2/instance.config.local.json")"
idx_before="$(GIT -C "$INST2" status --porcelain; GIT -C "$INST2" rev-parse HEAD)"

CHK2="$(bash "$SH" check --instance "$INST2" --template "$TPL" 2>&1)"
ok "check SEES the uncommitted config"                     "$(printf '%s\n' "$CHK2" | grep -c 'instance.config.json has uncommitted changes' | tr -d ' ')" 1
# Scoped to the warning line itself. `maxPrLoc` also appears in the config-LAYERS row's
# per-key listing, which is a different fact about a different question — counting both
# would make this assertion pass or fail on the other check's output.
ok "…and names the key that moved, not its value" \
  "$(printf '%s\n' "$CHK2" | grep '^⚠ instance.config.json has uncommitted' | grep -c 'maxPrLoc' | tr -d ' ')" 1
ok "…without printing the value anywhere"                  "$(printf '%s\n' "$CHK2" | grep -c '500' | tr -d ' ')" 0
ok "…and frames it as a question, not a defect"            "$(printf '%s\n' "$CHK2" | grep -c 'QUESTION, NOT A DEFECT' | tr -d ' ')" 1

FIX2="$(bash "$SH" fix --instance "$INST2" --template "$TPL" 2>&1)"
ok "fix reported it"                                       "$(printf '%s\n' "$FIX2" | grep -c 'config-uncommitted \[ambiguous\]' | tr -d ' ')" 1
# Under the row it belongs to, not merely somewhere in the output: awk takes the lines
# between this row's header and the next one. A bare count would pass with the refusal
# attached to the wrong check, which is the confusion the tiers exist to prevent.
ok "…and said so under that row, not as a footnote" \
  "$(printf '%s\n' "$FIX2" | awk '/^── config-uncommitted \[/{f=1;next} /^── /{f=0} f' \
     | grep -c 'NOT ACTED ON' | tr -d ' ')" 1
ok "instance.config.json is byte-identical after fix"      "$(sha "$INST2/instance.config.json")" "$cfg_before"
ok "instance.config.local.json is byte-identical after fix" "$(sha "$INST2/instance.config.local.json")" "$loc_before"
ok "…and nothing was staged, committed or reverted"        "$(GIT -C "$INST2" status --porcelain; GIT -C "$INST2" rev-parse HEAD)" "$idx_before"
ok "…and the local file still exists at all"               "$(yn test -f "$INST2/instance.config.local.json")" yes

# =======================================================================================
echo "== 5. SHIP-BLOCKER: fix never clears a tick lock, not even a stale one =="
# =======================================================================================
# `tick-lock.sh release` is the human's override. A tick that dispatched role agents can
# legitimately run long, so "stale" is a threshold and not a death certificate — clearing
# one on that evidence is the double-dispatch this machinery exists to prevent.
INST3="$TMP/inst3"; mkinstance "$INST3"
cp "$TPL/symlink/scripts/tick-lock.sh" "$INST3/scripts/tick-lock.sh"
old="$(date -u -r $(( $(date +%s) - 7200 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
printf 'timestamp: %s\nagent: project-manager\n' "$old" > "$INST3/.tick-lock"
printf 'timestamp: %s\nagent: project-manager\n' "$old" > "$INST3/.tick-lock.claim"

# The fixture is only worth anything if the machinery itself calls this lock stale — a
# two-hour-old lock that read as fresh would make the assertions below vacuous.
lockrc=0; lockout="$(bash "$INST3/scripts/tick-lock.sh" status --instance "$INST3" 2>&1)" || lockrc=$?
ok "the planted lock really is STALE to tick-lock.sh"      "$(printf '%s\n' "$lockout" | grep -c '^STALE' | tr -d ' ')" 1
ok "…which tick-lock.sh reports as exit 2"                 "$lockrc" 2

lock_before="$(sha "$INST3/.tick-lock")"
claim_before="$(sha "$INST3/.tick-lock.claim")"
CHK3="$(bash "$SH" check --instance "$INST3" --template "$TPL" 2>&1)"
ok "check SEES the stale lock"                             "$(printf '%s\n' "$CHK3" | grep -c 'tick lock needs YOUR decision' | tr -d ' ')" 1
ok "…and names release as the human's override"            "$(printf '%s\n' "$CHK3" | grep -c 'release --instance' | tr -d ' ')" 1

FIX3="$(bash "$SH" fix --instance "$INST3" --template "$TPL" 2>&1)"
ok "fix reported it at the human tier"                     "$(printf '%s\n' "$FIX3" | grep -c 'tick-lock \[human\]' | tr -d ' ')" 1
ok ".tick-lock still exists after fix"                     "$(yn test -f "$INST3/.tick-lock")" yes
ok "…byte-identical"                                       "$(sha "$INST3/.tick-lock")" "$lock_before"
ok ".tick-lock.claim still exists after fix"               "$(yn test -f "$INST3/.tick-lock.claim")" yes
ok "…byte-identical"                                       "$(sha "$INST3/.tick-lock.claim")" "$claim_before"
# And the lock is still doing its job: a dispatch after `fix` must still be refused.
arc=0; bash "$INST3/scripts/tick-lock.sh" acquire --instance "$INST3" >/dev/null 2>&1 || arc=$?
ok "…and the lock still refuses an acquire, so fix did not defeat it" \
  "$([ "$arc" -ne 0 ] && echo yes || echo no)" yes

# =======================================================================================
echo "== 6. the non-action is STRUCTURAL — the script refuses to carry a rogue fixer =="
# =======================================================================================
# A second, weaker net for the same class, and it is stated as one: it catches a fixer
# added for a print-only tier BEFORE it can ever run. The guard is provoked with a planted
# function, because a refusal that is never seen to fire is indistinguishable from a
# comment — and then the clean file is asserted NOT to refuse, so the check is not vacuous.
ok "no fix_ function exists for a print-only tier" \
  "$(for t in config_uncommitted tick_lock config_layers; do
       grep -c "^fix_$t()" "$SH"; done | awk '{s+=$1} END {print s+0}')" 0
ROGUE="$TMP/rogue.sh"
# BEFORE the call, not after: a function defined after `assert_no_rogue_fixers` runs would
# not be visible to it, and this test would then "pass" against a guard that never fired.
awk '/^assert_list_is_wired$/ && !d { print "fix_tick_lock() { :; }"; d=1 }
     { print }' "$SH" > "$ROGUE"
# The planted line must land BEFORE the call, or this proves nothing about ordering.
ok "the rogue fixture really does define one"              "$(grep -c '^fix_tick_lock()' "$ROGUE" | tr -d ' ')" 1
rrc=0; rout="$(bash "$ROGUE" check --instance "$INST1" --template "$TPL" 2>&1)" || rrc=$?
ok "a rogue fixer makes the command REFUSE TO RUN"         "$rrc" 2
ok "…naming the offending function"                        "$(printf '%s\n' "$rout" | grep -c 'fix_tick_lock' | tr -d ' ')" 1
ok "…and the shipped file does not refuse (not vacuous)"   "$(bash "$SH" check --instance "$INST1" --template "$TPL" >/dev/null 2>&1; echo $?)" 0
# The other half of the same guard: a row added WITHOUT its check function. Bash would call
# a command that does not exist, hand back 127, and this file's convention reads a non-zero
# return as "a problem was found" — so an idempotent row added with a typo would run its
# REPAIR on the strength of it. The guard must catch that before anything executes.
UNWIRED="$TMP/unwired.sh"
awk "/^CHECKS='/ { print; print \"invented-check|idempotent|yes\"; next } { print }" "$SH" > "$UNWIRED"
ok "the unwired fixture really does carry the extra row"   "$(grep -c '^invented-check|' "$UNWIRED" | tr -d ' ')" 1
urc=0; uout="$(bash "$UNWIRED" check --instance "$INST1" --template "$TPL" 2>&1)" || urc=$?
ok "a row with no check function makes it REFUSE TO RUN"   "$urc" 2
ok "…naming the unwired row"                               "$(printf '%s\n' "$uout" | grep -c 'invented-check' | tr -d ' ')" 1

# =======================================================================================
echo "== 7. fix ACTS on the idempotent tier — the other direction =="
# =======================================================================================
# A harness that only asserted the refusals would pass a `fix` that does nothing at all.
# This one stamps a real instance from a real template copy and asserts the missing links
# arrive. The template copy is a plain directory, not a worktree: install.sh refuses to run
# from one, before any write.
SRC="$TMP/tplcopy"; mkdir -p "$SRC"
( cd "$TPL" && tar cf - --exclude .git . ) | ( cd "$SRC" && tar xf - )
INST4="$TMP/inst4"; mkinstance "$INST4"
ok "before fix: SCHEMA.md is the instance's own stub, not a link" "$(yn test -L "$INST4/SCHEMA.md")" no
ok "before fix: no commit-as.sh"                           "$(yn test -e "$INST4/scripts/commit-as.sh")" no
FIX4="$(bash "$SH" fix --instance "$INST4" --template "$SRC" 2>&1)"
ok "fix ran the stamp"                                     "$(printf '%s\n' "$FIX4" | grep -c 'running: bash .*install.sh' | tr -d ' ')" 1
ok "…and the machinery arrived"                            "$(yn test -e "$INST4/scripts/commit-as.sh")" yes
ok "…as a symlink into the template"                       "$(yn test -L "$INST4/scripts/commit-as.sh")" yes
# IDEMPOTENT means a second run is a no-op, not a second outcome.
snap1="$(cd "$INST4" && find . -name .git -prune -o -print | sort | sed "s|^|$(echo)|")"
bash "$SH" fix --instance "$INST4" --template "$SRC" >/dev/null 2>&1
snap2="$(cd "$INST4" && find . -name .git -prune -o -print | sort | sed "s|^|$(echo)|")"
ok "running fix twice changes nothing the second time"     "$([ "$snap1" = "$snap2" ] && echo yes || echo no)" yes
CHK4="$(bash "$SH" check --instance "$INST4" --template "$SRC" 2>&1)"
ok "…and check now reports nothing left to stamp"          "$(printf '%s\n' "$CHK4" | grep -c 'nothing to stamp' | tr -d ' ')" 1

# =======================================================================================
echo "== 8. the SessionStart path: silent when clean, bounded when not =="
# =======================================================================================
# The banner's rule is ONLY FIRE WHAT IS TRUE — a block that prints every session becomes
# wallpaper, and wallpaper is how the lines that matter come to be skipped. So a healthy
# instance must produce BYTE-EMPTY output here, and an unhealthy one must stay short enough
# that the banner is still readable: the value of this section is that it names the repair,
# and a section that scrolled would lose that.
B4="$(bash "$SH" check --only-problems --banner --instance "$INST4" --template "$SRC" 2>&1)"
ok "a stamped instance adds BYTE-NOTHING to the banner"    "$(printf '%s' "$B4" | wc -c | tr -d ' ')" 0
B1="$(bash "$SH" check --only-problems --banner --instance "$INST1" --template "$TPL" 2>&1)"
ok "an unstamped one does speak (not vacuous)"             "$([ -n "$B1" ] && echo yes || echo no)" yes
ok "…and names the repair"                                 "$(printf '%s\n' "$B1" | grep -c 'install.sh' | tr -d ' ')" 1
ok "…in at most 2 lines per failing check, plus a header"  "$([ "$(printf '%s\n' "$B1" | grep -c .)" -le 4 ] && echo yes || echo no)" yes
# The rows that opted OUT of the banner must not appear there, or the banner says the same
# thing twice — it already prints the VERSION drift line and the config FROM column.
ok "a banner:no row stays off the banner path" \
  "$(printf '%s\n' "$B1" | grep -c 'config resolves' | tr -d ' ')" 0
# The hook actually calls it. Not "a function exists" — the shipped hook, by name.
# At least once, not exactly twice: the hook spells the call out in two branches today so a
# template path with a space survives, and pinning the count would fail a correct refactor.
ok "session-banner.sh invokes the check" \
  "$([ "$(grep -c 'ai-bridge.sh" check --only-problems --banner' "$BANNER" | tr -d ' ')" -ge 1 ] && echo yes || echo no)" yes
ok "…and the hook carries the name of no individual check" \
  "$(for id in $ids; do grep -c -- "$id" "$BANNER"; done | awk '{s+=$1} END {print s+0}')" 0

# =======================================================================================
echo "== 9. it ships like every other script here =="
# =======================================================================================
ok "ai-bridge.sh parses"                                   "$(yn bash -n "$SH")" yes
ok "…and is 100755 in the index"                           "$(cd "$TPL" && git ls-files -s symlink/scripts/ai-bridge.sh | awk '{print $1}')" 100755
ok "…and in HEAD"                                          "$(cd "$TPL" && git ls-tree HEAD symlink/scripts/ai-bridge.sh | awk '{print $1}')" 100755
ok "the command file ships"                                "$(yn test -f "$CMD")" yes
# `symlink/**` must carry no org, repo, path or channel literal — it is linked into every
# instance, whoever owns it.
ok "…and neither file hardcodes an org or a clone path" \
  "$(grep -c -E 'cbmono|/Users/|github\.com' "$SH" "$CMD" | awk -F: '{s+=$2} END {print s+0}')" 0

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
