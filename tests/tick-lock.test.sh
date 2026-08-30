#!/usr/bin/env bash
#
# tick-lock.test.sh — the dispatch lock has a REAL reader, and this is it.
#
# WHY THIS FILE IS BEHAVIOURAL AND NOT A GREP. `/pm-loop` has promised "at most one PM
# tick at a time" since it was written, and on 2026-08-29 two ticks ran concurrently for
# about 34 minutes anyway, because the promise was kept by the launching session
# REMEMBERING it had dispatched — and memory does not survive a compaction. That is the
# sixth rule in one month enforced by prose rather than by a mechanism (see the control
# panel's knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md), and a lock whose only
# test asserted that `pm-loop.md` mentions a lock would be the seventh. So the first half of
# this file drives the launcher's documented check-then-write path for real, against a real
# lock file on disk, including a genuine 20-way concurrent race; the document assertions in
# the second half only pin the WIRING, and are not what the criterion is satisfied by.
#
# THE FOUR PROPERTIES THAT ARE EASY TO GET BACKWARDS, each of which a reviewer should be
# able to refuse the change on, and each of which is asserted here:
#
#   1. ABSENCE IS NEVER AN ERROR. With no lock file the launcher dispatches exactly as it
#      did before this mechanism existed: silently, exit 0. The obvious implementation
#      inverts this and refuses to dispatch, which would break every instance on its first
#      upgrade. Asserted on the exit code AND on the output being byte-empty.
#   2. THE STALE PATH NEITHER STALLS NOR ADOPTS. Past the threshold the lock's timestamp
#      and agent id are surfaced, the file is NOT deleted and NOT rewritten, and no
#      dispatch happens. Silent deletion re-opens the double-dispatch; silent adoption is
#      the pressure that makes a stalled loop tempting to override.
#   3. IT IS PER CLONE, NOT CROSS-MACHINE. Two instance directories hold two independent
#      locks — because two humans sharing one bundle from two clones each dispatching is
#      the SUPPORTED design, not the bug. A test that let one lock refuse the other would
#      be pinning the wrong thing.
#   4. IT BOUNDS TICKS, NOT ROLE AGENTS. `maxAgentsInFlight` is the other concurrency
#      limit and is untouched; nothing on the role-agent path may read this file, or a
#      held lock would block the very agents the tick holding it dispatched.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
LOCKSH="$TPL/symlink/scripts/tick-lock.sh"
LAUNCHER="$TPL/symlink/.claude/commands/pm-loop.md"
TICK="$TPL/symlink/.claude/agents/project-manager.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tick-lock.XXXXXX")" || {
  echo "tick-lock.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}

# The same BSD-then-GNU order the script itself uses: `-r` is macOS's, `-d @…` is
# coreutils', and each is an error to the other.
iso_of() { # <epoch>
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# ============================================================ THE LAUNCHER, DRIVEN
# `/pm-loop` step 1, transcribed: resolve the model, run `acquire`, and spawn the tick if
# and ONLY if it exits 0 — with nothing between the acquire and the spawn. The spawn is a
# line appended to `dispatched.log`, which stands in for the `Agent` call a harness cannot
# make; everything the criterion is about (did a dispatch happen, and what decided it)
# is visible in that file.
ATTEMPT_RC=0; ATTEMPT_OUT=""
attempt() { # <instance-dir> [agent-id]
  local inst="$1" agent="${2:-project-manager}"
  ATTEMPT_OUT="$(bash "$LOCKSH" acquire --instance "$inst" --agent "$agent" 2>&1)"
  ATTEMPT_RC=$?
  [ "$ATTEMPT_RC" -eq 0 ] && printf 'tick dispatched: %s\n' "$agent" >> "$inst/dispatched.log"
  return 0
}
dispatches() { # <instance-dir> -> how many ticks the launcher actually spawned
  [ -f "$1/dispatched.log" ] && wc -l < "$1/dispatched.log" | tr -d ' ' || echo 0
}

echo "== absence is never an error: no lock, so it dispatches, in silence =="
A="$TMP/a"; mkdir -p "$A"
attempt "$A"
ok "exit 0 on a missing lock"            "$ATTEMPT_RC" 0
ok "…and it dispatched"                  "$(dispatches "$A")" 1
ok "…printing nothing at all"            "$ATTEMPT_OUT" ""
ok "…having created the lock"            "$(yn test -f "$A/.tick-lock")" yes
ok "…which names the agent"              "$(has "$A/.tick-lock" 'agent: project-manager')" yes
ok "…and an ISO-8601 UTC timestamp" \
  "$(grep -cE '^timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$A/.tick-lock" | tr -d ' ')" 1

echo
echo "== the same attempt against a FRESH lock does not dispatch =="
attempt "$A"
ok "exit 1 — held"                       "$ATTEMPT_RC" 1
ok "…and NO second tick was dispatched"  "$(dispatches "$A")" 1
ok "…saying a tick is in flight"         "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'HELD' && echo yes || echo no)" yes
ok "…and naming who holds it"            "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'project-manager' && echo yes || echo no)" yes

echo
echo "== release, and the very same attempt dispatches again =="
bash "$LOCKSH" release --instance "$A" >/dev/null 2>&1
ok "release exits 0"                     "$?" 0
ok "…and the lock is gone"               "$(yn test -e "$A/.tick-lock")" no
attempt "$A"
ok "exit 0 again"                        "$ATTEMPT_RC" 0
ok "…and it dispatched a second tick"    "$(dispatches "$A")" 2
# Releasing a lock nobody holds is the normal outcome of an interrupted loop, so it must
# be a silent success rather than a failure the launcher has to reason about.
bash "$LOCKSH" release --instance "$A" >/dev/null 2>&1
OUT="$(bash "$LOCKSH" release --instance "$A" 2>&1)"; RC=$?
ok "release on a missing lock: exit 0"   "$RC" 0
ok "…in silence"                         "$OUT" ""

echo
echo "== the race the mechanism exists for: 20 attempts, one dispatch =="
# The real property, not a proxy for it. `acquire` creates the file with O_EXCL, so the
# check and the write are one syscall and there is no window to interleave with — which is
# exactly what the tick's own ledger check (project-manager.md step 0.5) cannot claim,
# since it reads, then syncs, then writes.
R="$TMP/race"; mkdir -p "$R"
for i in $(seq 1 20); do
  ( bash "$LOCKSH" acquire --instance "$R" >/dev/null 2>&1 && : > "$R/won.$i" ) &
done
wait
ok "exactly one attempt won the lock" \
  "$(find "$R" -maxdepth 1 -name 'won.*' | wc -l | tr -d ' ')" 1
# NON-VACUITY: the same 20 parallel attempts must be able to produce 20 wins, or "one
# winner" would be a property of the loop rather than of the lock.
for i in $(seq 1 20); do
  ( mkdir -p "$TMP/solo/$i" && bash "$LOCKSH" acquire --instance "$TMP/solo/$i" >/dev/null 2>&1 \
    && : > "$TMP/solo/$i/won" ) &
done
wait
ok "…and 20 separate instances give 20 wins" \
  "$(find "$TMP/solo" -maxdepth 3 -name 'won' | wc -l | tr -d ' ')" 20

echo
echo "== stale: surfaced to the human, not deleted and not adopted =="
S="$TMP/stale"; mkdir -p "$S"
OLD=$(( $(date -u +%s) - 9000 ))          # 2h30m ago, past the 120m default
OLD_ISO="$(iso_of "$OLD")"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$S/.tick-lock"
BEFORE="$(cat "$S/.tick-lock")"
attempt "$S"
ok "exit 2 — a human decides"            "$ATTEMPT_RC" 2
ok "…and NOTHING was dispatched"         "$(dispatches "$S")" 0
ok "…it says STALE"                      "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'STALE' && echo yes || echo no)" yes
ok "…surfacing the lock's timestamp"     "$(printf '%s' "$ATTEMPT_OUT" | grep -qF "$OLD_ISO" && echo yes || echo no)" yes
ok "…and the agent id it names"          "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'agent:     project-manager' && echo yes || echo no)" yes
ok "…and the age it computed"            "$(printf '%s' "$ATTEMPT_OUT" | grep -qF '2h30m' && echo yes || echo no)" yes
ok "the lock was NOT deleted"            "$(yn test -f "$S/.tick-lock")" yes
ok "…and NOT rewritten (not adopted)"    "$( [ "$(cat "$S/.tick-lock")" = "$BEFORE" ] && echo yes || echo no)" yes
# The threshold is a knob, not a constant, and the same lock reads live under a bigger one
# — so "stale" is a computation over the file, not a property baked into the code path.
OUT="$(TICK_LOCK_STALE_MINUTES=600 bash "$LOCKSH" status --instance "$S" 2>&1)"; RC=$?
ok "…and a larger threshold reads it as held" "$RC" 1

echo
echo "== liveness is computed FROM THE FILE, timestamp alone is enough =="
# A lock carrying only the human-readable field still answers "is this stale?" — the
# criterion is that a reader never needs session memory, git log or the tick ledger.
T2="$TMP/tsonly"; mkdir -p "$T2"
printf 'timestamp: %s\nagent: cataloguer\n' "$OLD_ISO" > "$T2/.tick-lock"
attempt "$T2"
ok "exit 2 from the timestamp alone"     "$ATTEMPT_RC" 2
ok "…still no dispatch"                  "$(dispatches "$T2")" 0
ok "…naming the agent the file records"  "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'cataloguer' && echo yes || echo no)" yes

echo
echo "== a lock that cannot answer, and one dated in the future, both ask a human =="
U="$TMP/unreadable"; mkdir -p "$U"
printf 'this is not a lock\n' > "$U/.tick-lock"
attempt "$U"
ok "unreadable: exit 2"                  "$ATTEMPT_RC" 2
ok "…no dispatch"                        "$(dispatches "$U")" 0
ok "…and it is left on disk"             "$(yn test -f "$U/.tick-lock")" yes
F="$TMP/future"; mkdir -p "$F"
AHEAD=$(( $(date -u +%s) + 86400 ))
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$(iso_of "$AHEAD")" "$AHEAD" > "$F/.tick-lock"
attempt "$F"
# A future-dated lock can never age out, so treating it as merely "held" would stall the
# loop forever with nobody told why.
ok "future-dated: exit 2, not a silent wait" "$ATTEMPT_RC" 2
ok "…no dispatch"                        "$(dispatches "$F")" 0

echo
echo "== per clone, NOT cross-machine: two clones dispatch independently =="
# The supported design (`/pm-loop` -> "Why serial"; SCHEMA.md -> "Ownership on a shared
# instance"): two humans, one bundle, two clones. A lock that reached across them would
# break it, which is why it is gitignored and why this is asserted rather than assumed.
C1="$TMP/clone1"; C2="$TMP/clone2"; mkdir -p "$C1" "$C2"
attempt "$C1"; ok "clone 1 dispatches"   "$ATTEMPT_RC" 0
attempt "$C2"; ok "clone 2 dispatches too, while clone 1 holds" "$ATTEMPT_RC" 0
ok "…each holding its own lock" \
  "$( [ -f "$C1/.tick-lock" ] && [ -f "$C2/.tick-lock" ] && echo yes || echo no)" yes
attempt "$C1"; ok "…and clone 1 still refuses ITSELF" "$ATTEMPT_RC" 1

echo
echo "== it bounds TICKS, not role agents =="
# A held lock must never block the role agents the tick holding it dispatched, so nothing
# on that path may read the file. The check is that only the launcher and the script name
# it at all — no agent body does.
readers="$(grep -rlF 'tick-lock' "$TPL/symlink" 2>/dev/null | sed "s|^$TPL/||" | sort | tr '\n' ' ')"
ok "no agent file names the lock" \
  "$(printf '%s' "$readers" | grep -q 'symlink/.claude/agents/' && echo yes || echo no)" no
ok "the launcher does"                   "$(has "$LAUNCHER" 'scripts/tick-lock.sh')" yes
ok "…and says which limit this is"       "$(has "$LAUNCHER" 'bounds **PM')" yes
ok "…while the cap stays resolve-max-agents.sh" "$(has "$LAUNCHER" 'resolve-max-agents.sh')" yes
ok "the script says it reads no config"  "$(has "$LOCKSH" 'IT READS NO CONFIG')" yes

echo
echo "== the tick's own ledger is untouched: this ADDS a gate, it does not move one =="
ok "step 0.5 still opens a ledger entry" "$(has "$TICK" '* TICK <ISO-8601 timestamp> open:')" yes
ok "…still re-deriving from disk first"  "$(has "$TICK" 'Re-derive the in-flight set from disk')" yes
ok "…and the tick knows nothing of the lock" "$(has "$TICK" 'tick-lock')" no

echo
echo "== the wiring: the launcher runs the acquire, and holds exactly the grant for it =="
grants() { awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
  | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'; }
ok "allowed-tools grants the script"     "$(grants "$LAUNCHER" | grep -qx 'Bash(scripts/tick-lock.sh:\*)' && echo yes || echo no)" yes
ok "…and grants nothing else new"        "$(grants "$LAUNCHER" | wc -l | tr -d ' ')" 7
ok "step 1 runs the acquire"             "$(has "$LAUNCHER" 'scripts/tick-lock.sh acquire --agent project-manager')" yes
ok "…and step 2 releases on the notification" "$(has "$LAUNCHER" 'scripts/tick-lock.sh release')" yes
ok "…only on the notification, nothing weaker" "$(has "$LAUNCHER" 'before you schedule the gap')" yes
# Every exit code the script can return has a documented branch in the launcher, or the
# launcher would be improvising on the one that mattered.
step1() { awk '/^1\. \*\*Take the lock/{p=1;next} p&&/^2\. /{p=0} p' "$LAUNCHER"; }
for code in 0 1 2 3; do
  ok "step 1 handles exit $code"         "$(step1 | grep -qE "^   - \*\*$code\*\*" && echo yes || echo no)" yes
done
ok "step 1 forbids anything in between"  "$(step1 | grep -qF 'nothing may sit between the acquire and the spawn' && echo yes || echo no)" yes
ok "…and names the window it closes"     "$(step1 | grep -qF 'seconds to minutes' && echo yes || echo no)" yes
ok "…refusing to delete a stale lock itself" \
  "$(step1 | grep -qF "the human's answer, not yours" && echo yes || echo no)" yes

echo
echo "== the closed list gained ONE named exception, and stayed closed =="
section() { awk '/^### The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$LAUNCHER"; }
ok "the exception is named"              "$(section | grep -qF 'The one exception, named on purpose: the tick lock' && echo yes || echo no)" yes
ok "…and says it is not a precedent"     "$(section | grep -qF 'No other reader may be added by analogy' && echo yes || echo no)" yes
ok "…keeping the economy justification"  "$(section | grep -qF "main session's context" && echo yes || echo no)" yes
# Every source the rule forbade is still forbidden by name in that same section. This is
# the half that would rot if the exception were ever widened into a relaxation.
missing=0
for src in 'log.md' 'tick ledger' 'task documents' 'AWAITING.md' 'SNAPSHOT.json' \
           'worktree listing' 'git status' 'git log' 'gh repo view' 'gh pr list'; do
  section | grep -qF -- "$src" || { echo "  (no longer forbidden: $src)"; missing=$((missing+1)); }
done
ok "…and all ten forbidden sources remain" "$missing" 0

echo
echo "== the lock is gitignored on a freshly stamped instance =="
# install.sh refuses to run from a linked git worktree (its own header says why, and every
# role agent's checkout of this template is one), so stamp from a filesystem copy taken
# outside any repo — the same dance tests/derived-indexes.test.sh does, and see there for
# the full rationale and this TMPDIR-recursion guard.
BRIDGE_INSTALL="$TPL/install.sh"
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    _tpl_res="$(cd -- "$TPL" && pwd -P)"
    _src_res="$(cd -- "$TMP" && pwd -P)"
    case "$_src_res/" in
      "$_tpl_res"/*) echo "tick-lock.test: TMPDIR ($_src_res) is inside the template tree ($_tpl_res); the install-source copy would recurse. Point TMPDIR outside the checkout." >&2; exit 2 ;;
    esac
    mkdir -p "$INSTALL_SRC"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/install.sh"
  fi
fi
ok "seed/.gitignore carries the line"    "$(grep -qxF '/.tick-lock' "$TPL/seed/.gitignore" && echo yes || echo no)" yes
INST="$TMP/g/_ai-bridge-g"; mkdir -p "$INST"
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a fresh stamp gets the line"         "$(grep -qxF '/.tick-lock' "$INST/.gitignore" && echo yes || echo no)" yes
( cd "$INST" && git init -q . && git config user.email t@e.st && git config user.name t )
printf 'agent: x\n' > "$INST/.tick-lock"
# git's own answer, not the pattern text — the same standard derived-indexes.test.sh holds
# its lines to.
ok "git itself ignores the lock"         "$( ( cd "$INST" && git check-ignore -q .tick-lock ) && echo yes || echo no)" yes
( cd "$INST" && git add -A >/dev/null 2>&1 )
ok "…so a git add -A never stages it" \
  "$( ( cd "$INST" && git diff --cached --name-only ) | grep -qxF '.tick-lock' && echo yes || echo no)" no
# And it must reach an instance whose .gitignore predates the line — which is every
# instance in existence — exactly once, not once per stamp.
grep -v '^/\.tick-lock$' "$INST/.gitignore" > "$INST/.gi" && mv "$INST/.gi" "$INST/.gitignore"
ok "…(removed for the re-stamp)"         "$(grep -cxF '/.tick-lock' "$INST/.gitignore" | tr -d ' ')" 0
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a re-stamp appends it back"          "$(grep -cxF '/.tick-lock' "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "…and a third stamp adds no duplicate" "$(grep -cxF '/.tick-lock' "$INST/.gitignore" | tr -d ' ')" 1

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
