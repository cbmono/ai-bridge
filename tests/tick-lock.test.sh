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
# AND TWO MORE, ADDED 2026-08-30 AFTER THE MECHANISM SHIPPED AND THE BUG HAPPENED ANYWAY.
# About an hour after the lock merged, two `project-manager` agents ran at once: one was
# **resumed** with a message rather than dispatched, so it never passed through the launcher,
# took no lock, and was invisible to one. The guard behaved exactly as designed. So:
#
#   5. THE TICK TAKES THE LOCK TOO, NOT ONLY THE LAUNCHER. A tick that began without a
#      dispatch acquires it, and a later acquire sees it held. Everything above this line
#      passed while that gap was open, which is precisely how it survived a whole harness:
#      a mechanism on the path you were thinking about is not a mechanism on every path.
#   6. AND A DISPATCHED TICK MUST NOT REFUSE ITS OWN LOCK — the crux, and the failure mode
#      of the obvious fix. The launcher takes the lock and then spawns; the tick then finds
#      a held lock that is its own. Get that wrong and EVERY dispatched tick deadlocks on
#      entry, a total outage strictly worse than the concurrency bug. So the sequence is
#      driven here for real, in order, and the tick is asserted to PROCEED — and to proceed
#      by ADOPTING (`adopted:`) rather than by taking a lock of its own, because a tick that
#      "proceeded" because the lock had vanished would pass a weaker test for the wrong
#      reason.
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

# And the TICK's own step 0.5, transcribed the same way: `project-manager.md` runs the
# acquire before it re-derives anything, and does its tick if and only if that exits 0. A
# line in `ran.log` stands in for the tick actually running. `dispatched.log` counts what
# the launcher spawned; `ran.log` counts what actually RAN — and the two differ precisely
# in the cases this file was extended for, which is why they are counted separately.
TICK_RC=0; TICK_OUT=""
tick() { # <instance-dir> [agent-id] — a tick reaching its step 0.5, however it began
  local inst="$1" agent="${2:-project-manager}"
  TICK_OUT="$(bash "$LOCKSH" acquire --as tick --instance "$inst" --agent "$agent" 2>&1)"
  TICK_RC=$?
  [ "$TICK_RC" -eq 0 ] && printf 'tick ran: %s\n' "$agent" >> "$inst/ran.log"
  return 0
}
ran() { # <instance-dir> -> how many ticks actually proceeded past step 0.5
  [ -f "$1/ran.log" ] && wc -l < "$1/ran.log" | tr -d ' ' || echo 0
}
said() { # <fixed-string> -> yes|no, against the last tick's output
  printf '%s' "$TICK_OUT" | grep -qF -- "$1" && echo yes || echo no
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
echo "== THE CRUX: the launcher takes it, then the tick it spawned takes it and PROCEEDS =="
# The real sequence, in order, with nothing mocked: /pm-loop step 1 acquires and spawns;
# project-manager.md step 0.5 acquires. If the tick cannot tell "held by the launcher that
# spawned me" from "held by someone else", this is where every dispatched tick deadlocks —
# an outage of the whole loop, worse than the bug being fixed.
H="$TMP/handoff"; mkdir -p "$H"
attempt "$H"
ok "the launcher took the lock"          "$ATTEMPT_RC" 0
ok "…and spawned a tick"                 "$(dispatches "$H")" 1
tick "$H"
ok "the tick it spawned PROCEEDS"        "$TICK_RC" 0
ok "…and actually ran"                   "$(ran "$H")" 1
ok "…by adopting the launcher's lock"    "$(said 'adopted:')" yes
# Not by taking one of its own: a tick that "proceeded" because the lock had gone would
# pass the exit-code assertion above for entirely the wrong reason.
ok "…not by taking a lock of its own"    "$(said 'took:')" no
ok "…and the lock is still the launcher's one lock" \
  "$(yn test -f "$H/.tick-lock")" yes
ok "…now carrying the tick's claim"      "$(yn test -f "$H/.tick-lock.claim")" yes

echo
echo "== …and a DIFFERENT tick, at that same lock, reports and holds =="
# The resumed tick of 2026-08-30 arriving while a dispatched one is running.
tick "$H" cataloguer
ok "the second tick is refused"          "$TICK_RC" 1
ok "…and did NOT run"                    "$(ran "$H")" 1
ok "…saying another tick holds it"       "$(said 'HELD BY ANOTHER TICK')" yes
ok "…naming who claimed it"              "$(said 'project-manager')" yes
ok "…and telling it to hold, not adopt"  "$(said 'adopt nothing')" yes
ok "…and to release nothing"             "$(said 'release nothing')" yes
# The launcher, meanwhile, sees exactly what it saw before this change: a held lock.
attempt "$H"
ok "the launcher still just sees HELD"   "$ATTEMPT_RC" 1
ok "…and dispatched nothing more"        "$(dispatches "$H")" 1
ok "…and can see the tick is RUNNING, not merely dispatched" \
  "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'it is RUNNING' && echo yes || echo no)" yes

echo
echo "== the measured bug: a RESUMED tick takes the lock, and a dispatch then sees it =="
# The whole point. `SendMessage` wakes a completed agent directly — no launcher, no
# acquire — so before this change nothing was written and the next dispatch correctly
# found the lock free. Two project-managers ran concurrently for exactly that reason.
R2="$TMP/resume"; mkdir -p "$R2"
tick "$R2"                                # resumed: it did not pass through the launcher
ok "the resumed tick proceeds"           "$TICK_RC" 0
ok "…and took the lock ITSELF"           "$(said 'took:')" yes
ok "…so the lock now exists"             "$(yn test -f "$R2/.tick-lock")" yes
ok "…already claimed, since it is running" "$(yn test -f "$R2/.tick-lock.claim")" yes
attempt "$R2"
ok "the launcher is refused"             "$ATTEMPT_RC" 1
ok "…and dispatches NOTHING"             "$(dispatches "$R2")" 0
ok "…so exactly one tick ran"            "$(ran "$R2")" 1

echo
echo "== two concurrent ticks cannot both proceed, whichever order they arrive in =="
# Order A is the paragraph above (resume first, dispatch refused). Order B is the launcher
# first: the resumed tick adopts the dispatch lock and the dispatched tick then holds —
# still exactly one tick running, which is the property, though not the same one.
B="$TMP/order-b"; mkdir -p "$B"
attempt "$B"                              # launcher takes the lock…
tick "$B" cataloguer                      # …a resumed tick gets to step 0.5 first
tick "$B" project-manager                 # …and the dispatched tick arrives after
ok "exactly one of the two ticks ran"    "$(ran "$B")" 1
ok "…and it is the one that got there first" \
  "$(grep -c 'cataloguer' "$B/ran.log" | tr -d ' ')" 1

echo
echo "== 20 ticks racing for ONE unclaimed dispatch lock: exactly one adopts it =="
# The claim is created with O_EXCL for the same reason the lock is. A claim written by
# read-then-write would re-open, one layer down, the very race `acquire` exists to close —
# and it would do it in the adoption path, which is the one nobody would think to test.
A2="$TMP/adopt-race"; mkdir -p "$A2"
bash "$LOCKSH" acquire --instance "$A2" >/dev/null 2>&1     # the launcher's lock
for i in $(seq 1 20); do
  ( bash "$LOCKSH" acquire --as tick --instance "$A2" >/dev/null 2>&1 && : > "$A2/adopted.$i" ) &
done
wait
ok "exactly one tick adopted it" \
  "$(find "$A2" -maxdepth 1 -name 'adopted.*' | wc -l | tr -d ' ')" 1

echo
echo "== the claim is part of the lock, not a second clock and not a second lock =="
# A tick must not be able to refresh its own deadline by claiming: staleness is computed
# from `.tick-lock` alone, exactly as before this change.
SC="$TMP/stale-claim"; mkdir -p "$SC"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$SC/.tick-lock"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$(iso_of "$(date -u +%s)")" "$(date -u +%s)" \
  > "$SC/.tick-lock.claim"
attempt "$SC"
ok "a fresh claim does not rejuvenate a stale lock" "$ATTEMPT_RC" 2
ok "…and it still says STALE"            "$(printf '%s' "$ATTEMPT_OUT" | grep -qF 'STALE' && echo yes || echo no)" yes
tick "$SC"
ok "…and a TICK gets the same verdict, not an adoption" "$TICK_RC" 2
ok "…so it did not run"                  "$(ran "$SC")" 0
# `release` is the human's override and stays unconditional — it asks nobody who they are,
# and it takes the claim with the lock rather than leaving half a mechanism behind.
bash "$LOCKSH" release --instance "$SC"
ok "release clears the lock"             "$(yn test -e "$SC/.tick-lock")" no
ok "…and the claim with it"              "$(yn test -e "$SC/.tick-lock.claim")" no
OUT="$(bash "$LOCKSH" release --as tick --instance "$SC" 2>&1)"; RC=$?
ok "release refuses an identity argument" "$RC" 3
ok "…saying it is unconditional"         "$(printf '%s' "$OUT" | grep -qF 'unconditional' && echo yes || echo no)" yes

echo
echo "== a claim that outlived its lock is residue, and must not deadlock the next tick =="
# The other way to get this wrong: leave a claim behind (a hand-removed lock, a release
# that died between its two rm's) and every subsequently dispatched tick refuses a lock
# nobody holds. `acquire` clears it on the create — and only when it was there BEFORE the
# create, so it can never delete a live tick's claim.
RS="$TMP/residue"; mkdir -p "$RS"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$RS/.tick-lock.claim"
ok "status says the claim outlived its lock" \
  "$(bash "$LOCKSH" status --instance "$RS" 2>&1 | grep -qF 'outlived' && echo yes || echo no)" yes
attempt "$RS"
ok "the launcher still dispatches"       "$ATTEMPT_RC" 0
ok "…having cleared the residue"         "$(yn test -e "$RS/.tick-lock.claim")" no
tick "$RS"
ok "…and its tick is not deadlocked by it" "$TICK_RC" 0
ok "…and ran"                            "$(ran "$RS")" 1

echo
echo "== absence is never an error on the tick's path either =="
N="$TMP/tick-absent"; mkdir -p "$N"
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$N" 2>/dev/null)"; RC=$?
ok "no lock: the tick takes one and runs" "$RC" 0
ok "…and says so on stdout, not stderr"  "$(printf '%s' "$OUT" | grep -qF 'took:' && echo yes || echo no)" yes
# The launcher's path stays byte-silent — that contract is unchanged and is asserted at the
# top of this file; what follows only pins that `--as` is validated rather than assumed.
OUT="$(bash "$LOCKSH" acquire --as sideways --instance "$N" 2>&1)"; RC=$?
ok "an unknown --as is refused"          "$RC" 3
ok "…naming the two it accepts"          "$(printf '%s' "$OUT" | grep -qF 'launcher or tick' && echo yes || echo no)" yes
OUT="$(bash "$LOCKSH" acquire --as --instance "$N" 2>&1)"; RC=$?
ok "a bare trailing --as is refused too" "$RC" 3

echo
echo "== a claim that cannot be WRITTEN is not a claim somebody else holds =="
# Two causes, two answers — the distinction `acquire` already refuses to collapse for the
# lock. Collapsing it here would report an unwritable instance root as "another tick is
# running", which is the one message nobody would think to debug.
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP  running as root: permission bits refuse nobody"
else
  W="$TMP/readonly"; mkdir -p "$W"
  attempt "$W"                              # the launcher takes the lock while it can
  chmod a-w "$W"
  tick "$W"; RC_RO="$TICK_RC"; OUT_RO="$TICK_OUT"
  REL_OUT="$(bash "$LOCKSH" release --instance "$W" 2>&1)"; REL_RC=$?
  chmod u+w "$W"                            # …restored before anything else runs
  ok "the tick refuses with exit 3"        "$RC_RO" 3
  ok "…naming the unwritable root"         "$(printf '%s' "$OUT_RO" | grep -qF 'not writable' && echo yes || echo no)" yes
  ok "…and NOT blaming another tick"       "$(printf '%s' "$OUT_RO" | grep -qF 'HELD BY ANOTHER TICK' && echo yes || echo no)" no
  ok "…so it did not run"                  "$(ran "$W")" 0
  # And a release that cannot remove says which file it left, rather than reporting a
  # success the caller would take as "the lock is gone".
  ok "a release that cannot remove exits 3" "$REL_RC" 3
  ok "…naming the file still on disk"      "$(printf '%s' "$REL_OUT" | grep -qF '.tick-lock' && echo yes || echo no)" yes
fi

echo
echo "== it bounds TICKS, not role agents =="
# A held lock must never block the role agents the tick holding it dispatched, so nothing on
# THAT path may read the file. This assertion was "no agent names the lock" until 2026-08-30
# and is now an exact set, deliberately: the tick had to become a reader (property 5 above),
# and "no agent" would have had to be deleted to let it, which is how a guard quietly becomes
# "some agents". Naming the one file that may read it keeps the other half enforced — add a
# second agent to this list and you are back to a held lock blocking role agents.
agent_readers="$(grep -rlF 'tick-lock' "$TPL/symlink/.claude/agents" 2>/dev/null \
  | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ *$//')"
ok "exactly one agent may name the lock — the tick" "$agent_readers" "project-manager.md"
ok "the launcher does"                   "$(has "$LAUNCHER" 'scripts/tick-lock.sh')" yes
ok "…and says which limit this is"       "$(has "$LAUNCHER" 'bounds **PM')" yes
ok "…while the cap stays resolve-max-agents.sh" "$(has "$LAUNCHER" 'resolve-max-agents.sh')" yes
ok "the script says it reads no config"  "$(has "$LOCKSH" 'IT READS NO CONFIG')" yes

echo
echo "== the tick's own ledger is untouched: this ADDS a gate, it does not move one =="
ok "step 0.5 still opens a ledger entry" "$(has "$TICK" '* TICK <ISO-8601 timestamp> open:')" yes
ok "…still re-deriving from disk first"  "$(has "$TICK" 're-derive the in-flight set from disk')" yes

echo
echo "== the second acquire site: the TICK takes the lock, and holds when it is another's =="
# This assertion is the exact inverse of the one that stood here until 2026-08-30 ("the tick
# knows nothing of the lock"). It was a faithful pin of the design that shipped, and the
# design was wrong: the launcher is on one of the two paths that start a tick, and the other
# one — a resume — is where two project-managers ran at once. Inverted deliberately, in the
# same change that puts the acquire in the tick, so neither half can drift from the other.
step05() { awk '/^0\.5\. \*\*Take the tick lock/{p=1;next} p&&/^1\. \*\*Orient/{p=0} p' "$TICK"; }
ok "step 0.5 runs the tick's own acquire" \
  "$(step05 | grep -qF 'scripts/tick-lock.sh acquire --as tick' && echo yes || echo no)" yes
ok "…before it re-derives anything"      "$(step05 | grep -qF 'The lock comes first' && echo yes || echo no)" yes
# Every exit code the script can return has a branch here too — the launcher's step 1 has
# had one since #62, and a second caller with three of the four is a caller improvising on
# the one that mattered.
for code in 0 1 2 3; do
  ok "step 0.5 handles exit $code"       "$(step05 | grep -qE "^   - \*\*$code\*\*" && echo yes || echo no)" yes
done
ok "…holding, not adopting, on a live sibling" \
  "$(step05 | grep -qF 'adopt nothing as your in-flight set' && echo yes || echo no)" yes
ok "…and opening no ledger entry when it holds" \
  "$(step05 | grep -qF 'open no ledger entry' && echo yes || echo no)" yes
ok "…and never deleting a stale lock itself" \
  "$(step05 | grep -qF 'their answer, not' && echo yes || echo no)" yes
ok "…naming the path the launcher is not on" \
  "$(step05 | grep -qF 'a resume never' && echo yes || echo no)" yes
# The release obligation from #62 is unchanged and now has a second caller, so the tick has
# to say which lock is its own to release. A tick that released an ADOPTED lock would free
# one the launcher is still holding for it.
rel() { awk '/\*\*Finally, release the tick lock/{p=1} p&&/^9\. /{p=0} p' "$TICK"; }
ok "step 8 releases only a lock the tick created" \
  "$(rel | grep -qF 'ONLY if step 0.5 printed `took:`' && echo yes || echo no)" yes
ok "…leaving an adopted one to the launcher" \
  "$(rel | grep -qF 'adopted:' && echo yes || echo no)" yes
ok "…and a tick that held releases nothing" \
  "$(rel | grep -qF 'releases nothing at all' && echo yes || echo no)" yes

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

# STOPPING THE LOOP MUST NOT RELEASE SOMEBODY ELSE'S LOCK. `release` holds no session
# identity — it is the human's override and cannot have one — so the condition has to live
# in the caller. A session that skipped at step 1 because another loop held the lock, and
# then released on its way out, would delete a LIVE holder's lock and re-open exactly the
# double-dispatch this file closes. Raised by review on ai-bridge#62.
step5() { awk '/^5\. \*\*Stop\*\*/{p=1;next} p&&/^[A-Za-z]/{p=0} p' "$LAUNCHER"; }
ok "step 5 releases only a lock this session took" \
  "$(step5 | grep -qF 'only if THIS session took it' && echo yes || echo no)" yes
ok "…naming the sibling it would otherwise delete" \
  "$(step5 | grep -qF 'live' && echo yes || echo no)" yes
ok "…and leaves a dispatched tick's lock to age out" \
  "$(step5 | grep -qF 'ages out' && echo yes || echo no)" yes
# And clearance to dispatch is the lock being CREATED, not merely missing: an unwritable
# root refuses rather than dispatching unguarded, which is the other way "absence is never
# an error" gets read backwards.
ok "the script says a failed create refuses" "$(has "$LOCKSH" 'A FAILED CREATE IS')" yes
ok "…and the operator docs say so too" \
  "$(has "$TPL/docs/operations.md" 'Dispatch follows the lock being')" yes

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
echo "== …and so is the claim beside it, under its OWN guard =="
# `/.tick-lock` does not match `.tick-lock.claim`, so the claim needs its own line — and,
# more importantly, its own GUARD. Every instance stamped since the lock shipped already
# carries `/.tick-lock`, which satisfies that guard, so a line added inside its heredoc
# would reach exactly nobody who has the first one. That is the case asserted here: remove
# ONLY the claim line, leave the lock's, and a re-stamp must still append it.
ok "seed/.gitignore carries the claim too" "$(grep -qxF '/.tick-lock.claim' "$TPL/seed/.gitignore" && echo yes || echo no)" yes
ok "a fresh stamp gets it"               "$(grep -cxF '/.tick-lock.claim' "$INST/.gitignore" | tr -d ' ')" 1
printf 'agent: x\n' > "$INST/.tick-lock.claim"
ok "git itself ignores the claim"        "$( ( cd "$INST" && git check-ignore -q .tick-lock.claim ) && echo yes || echo no)" yes
( cd "$INST" && git add -A >/dev/null 2>&1 )
ok "…so a git add -A never stages it" \
  "$( ( cd "$INST" && git diff --cached --name-only ) | grep -qxF '.tick-lock.claim' && echo yes || echo no)" no
grep -v '^/\.tick-lock\.claim$' "$INST/.gitignore" > "$INST/.gi" && mv "$INST/.gi" "$INST/.gitignore"
ok "…(removed, with the lock's line left in place)" \
  "$(grep -cxF '/.tick-lock' "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a re-stamp appends the claim anyway" "$(grep -cxF '/.tick-lock.claim' "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "…and a third stamp adds no duplicate" "$(grep -cxF '/.tick-lock.claim' "$INST/.gitignore" | tr -d ' ')" 1

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
