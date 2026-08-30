#!/usr/bin/env bash
#
# tick-lock.sh — the one-tick-at-a-time guarantee, as a file instead of a memory.
#
#   Usage: scripts/tick-lock.sh acquire [--agent <id>] [--instance DIR]
#          scripts/tick-lock.sh release [--instance DIR]
#          scripts/tick-lock.sh status  [--instance DIR]
#
# WHY THIS EXISTS. `/pm-loop` promises at most one PM tick at a time. Until this script,
# that promise rested on TWO things, and neither is a mechanism:
#
#   1. THE LAUNCHING SESSION REMEMBERING IT DISPATCHED. `/pm-loop` step 4 defines "still
#      in flight" as "this session dispatched a tick and has not yet seen its
#      notification" — answered from session history, which a compaction, a `--resume` or
#      a human asking "what's next?" all discard. Measured 2026-08-29 in a real instance:
#      two ticks ran concurrently for ~34 minutes, doing the same refinement work twice.
#      The session that caused it said so plainly — "I dispatched a second tick before the
#      first one's completion notification arrived."
#   2. THE TICK'S OWN LEDGER CHECK (`project-manager.md` step 0.5), which is real and
#      well-written and CANNOT close this window, because it runs INSIDE the tick:
#
#        launcher dispatches A ──► A: step 0 `git pull` ──► A: 0.5 checks ──► A writes "open"
#                            ▲
#              a tick dispatched anywhere in here sees NO open entry
#
#      Seconds to minutes in which the ledger truthfully reports nothing running. That
#      ledger is untouched by this script and stays the TICK's own record; this is a
#      second, earlier gate, at the only moment anybody knows "I am dispatching right now".
#
# THE CHECK AND THE WRITE ARE ONE SYSCALL, WHICH IS THE POINT. `acquire` creates the lock
# under `set -o noclobber` — an `O_EXCL` create. There is no read-then-write to interleave,
# so the window that defeated the ledger check does not exist here even in principle. That
# is also why `status` exists as a SEPARATE subcommand and why the launcher must never call
# it: `status` then `acquire` would rebuild the very TOCTOU race this replaces.
#
# LIVENESS IS DATA, NOT A JUDGEMENT. The lock carries an ISO-8601 UTC timestamp and the id
# of the agent that was dispatched, so "is this stale?" is computed from the file alone —
# never from session memory, `git log` or the tick ledger, none of which can answer it. A
# lock past `TICK_LOCK_STALE_MINUTES` (default 120) is NOT silently deleted and NOT
# silently treated as live: both are refused on purpose, because silent deletion re-opens
# the double-dispatch and silent adoption is the pressure that makes overriding a stalled
# loop tempting. It is surfaced — timestamp, agent, age, path — and a human decides.
#
# IT IS A PER-CLONE LOCK AND IT MUST NOT PRETEND OTHERWISE. The file is gitignored and
# lives in one working tree. Two humans sharing one bundle from two clones each dispatch
# independently, which is the SUPPORTED design (`/pm-loop` → "Why serial"; SCHEMA.md →
# "Ownership on a shared instance"), and a committed or shared lock would break it. What
# stops those two loops dispatching the same TASK is `scripts/task-owner.sh`, not this.
#
# IT BOUNDS TICKS, NOT ROLE AGENTS. `maxAgentsInFlight` (via `scripts/resolve-max-agents.sh`)
# is the other concurrency limit and is untouched: it caps the role agents a tick dispatches.
# A held lock must never block those — nothing in the role-agent path reads this file.
#
# ABSENCE IS NEVER AN ERROR. No lock ⇒ `acquire` takes it and says nothing (exit 0), which
# is the launcher behaving exactly as it did before this file existed. `release` on a
# missing lock is a silent success too. The only silence this script breaks is a refusal.
#
# IT READS NO CONFIG. `TICK_LOCK_STALE_MINUTES` is an environment override in the shape
# `prune-worktrees.sh` already uses for `PRUNE_ACTIVE_MINUTES`; there is deliberately no
# `instance.config.json` key, so this adds nothing to the overridable-key surface.
#
# Exit codes — 0 is the only clearance to dispatch:
#
#   0  acquire: the lock is now yours, dispatch.   release/status: nothing is held.
#   1  HELD — a live lock, younger than the staleness threshold. Do not dispatch.
#   2  needs a human: the lock is STALE, dated in the future, or unreadable. Do not
#      dispatch, and do not delete it on the lock's behalf.
#   3  cannot answer: usage, a bad `--agent`/threshold, or an unwritable instance root.
#      Never a silent pass — a lock nothing can write is a guarantee nothing is keeping.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/tick-lock.test.sh.
set -uo pipefail

LOCK_NAME=".tick-lock"

usage() {
  echo "Usage: $(basename "$0") acquire [--agent <id>] [--instance DIR]" >&2
  echo "       $(basename "$0") release [--instance DIR]" >&2
  echo "       $(basename "$0") status  [--instance DIR]" >&2
  exit 3
}

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in
  acquire|release|status) ;;
  -h|--help) sed -n '3,8p' "$0"; exit 0 ;;
  *) usage ;;
esac

inst="."
agent="project-manager"
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` before every `shift 2`: a bare trailing flag leaves one argument and
    # `shift 2` then FAILS WITHOUT SHIFTING, which with no `set -e` spins this loop
    # forever on the same argv — the bug resolve-model.sh hit and resolve-max-agents.sh
    # records.
    --instance)
      [ $# -ge 2 ] || { echo "tick-lock: --instance needs a directory" >&2; exit 3; }
      inst="$2"; shift 2 ;;
    --agent)
      [ $# -ge 2 ] || { echo "tick-lock: --agent needs an id" >&2; exit 3; }
      agent="$2"; shift 2 ;;
    *) echo "tick-lock: unexpected argument $1" >&2; usage ;;
  esac
done

[ -d "$inst" ] || { echo "tick-lock: no such instance directory: $inst" >&2; exit 3; }
LOCK="$inst/$LOCK_NAME"

# The agent id goes into the file verbatim, so it is constrained to what an agent id can
# actually be. Not politeness: an unconstrained value could carry a newline and forge a
# second field, which would make a lock say whatever the caller wanted it to say.
case "$agent" in
  ''|*[!A-Za-z0-9._-]*)
    echo "tick-lock: --agent must be a plain id ([A-Za-z0-9._-]), got: $agent" >&2; exit 3 ;;
esac

# Refused rather than rounded, for the reason resolve-max-agents.sh refuses a bad cap: a
# threshold nobody can read is worse than one that says it does not know. `0` is rejected
# too — it would make every lock instantly stale, i.e. silently turn the mechanism off.
STALE_MINUTES="${TICK_LOCK_STALE_MINUTES:-120}"
case "$STALE_MINUTES" in
  ''|*[!0-9]*|0)
    echo "tick-lock: TICK_LOCK_STALE_MINUTES must be a positive integer, got: $STALE_MINUTES" >&2
    exit 3 ;;
esac
STALE_SECONDS=$((STALE_MINUTES * 60))

NOW="$(date -u +%s)"

# --- reading a lock -------------------------------------------------------------------
# Only the FIRST occurrence of a key counts, and `#` lines are comments — the same reader
# discipline check-dispatch.sh uses, for the same reason: a repeated key must not be judged
# from the later value.
lock_field() { # <key>
  awk -v key="$1" '
    /^[[:space:]]*#/ { next }
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }' "$LOCK" 2>/dev/null
}

# BSD first, then GNU: `date -j` is macOS's and `date -d` is coreutils', each is an illegal
# option to the other, and this repo's suite runs on macOS while instances run on both.
# Only an all-digits answer is accepted, so a shell that "succeeds" while printing a usage
# banner cannot become a timestamp.
iso_to_epoch() { # <iso-8601 UTC>
  local out
  out="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null)" \
    || out="$(date -u -d "$1" +%s 2>/dev/null)"
  case "$out" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$out"
}

# The lock's age in seconds, or nothing when the file cannot answer. `epoch:` is preferred
# because it needs no parsing; `timestamp:` is the fallback so a hand-written lock carrying
# only the human-readable field still works.
lock_age() {
  local e ts
  e="$(lock_field epoch)"
  case "$e" in ''|*[!0-9]*) e="" ;; esac
  if [ -z "$e" ]; then
    ts="$(lock_field timestamp)"
    [ -n "$ts" ] && e="$(iso_to_epoch "$ts")"
  fi
  [ -n "$e" ] || return 1
  printf '%s' "$((NOW - e))"
}

human_age() { # <seconds>
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ss' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%sm' "$((s / 60))"
  else printf '%sh%sm' "$((s / 3600))" "$(((s % 3600) / 60))"; fi
}

# Judge an EXISTING lock. Prints the verdict and returns the exit code the caller uses, so
# `acquire` and `status` cannot drift apart about what "stale" means.
judge_existing() {
  local ts ag age
  ts="$(lock_field timestamp)"
  ag="$(lock_field agent)"
  age="$(lock_age)" || age=""

  if [ -z "$ts" ] || [ -z "$ag" ] || [ -z "$age" ]; then
    echo "UNREADABLE: $LOCK exists but does not say when it was taken or by whom," >&2
    echo "            so whether a tick is running cannot be computed from it. Refusing" >&2
    echo "            rather than guessing. Read the file, then either fix it or run:" >&2
    echo "              scripts/tick-lock.sh release" >&2
    return 2
  fi

  # A lock dated in the future never ages out, so it would stall the loop forever in the
  # "held" branch. Slop of 60s absorbs ordinary clock drift; past that it is an anomaly a
  # human should see, not a lock to wait on.
  if [ "$age" -lt -60 ]; then
    echo "AHEAD OF THE CLOCK: $LOCK is dated $ts, which is in the future." >&2
    echo "                    agent: $ag" >&2
    echo "                    A clock change or a hand-edit does this. It cannot go" >&2
    echo "                    stale on its own — decide, then release it if it is dead." >&2
    return 2
  fi

  if [ "$age" -ge "$STALE_SECONDS" ]; then
    echo "STALE: $LOCK was taken $(human_age "$age") ago, past the ${STALE_MINUTES}m threshold." >&2
    echo "       timestamp: $ts" >&2
    echo "       agent:     $ag" >&2
    echo "       This is NOT deleted for you and NOT assumed dead: a tick that dispatched" >&2
    echo "       role agents can legitimately run long, and deleting a live tick's lock is" >&2
    echo "       the double-dispatch this file exists to prevent. Decide, then either wait" >&2
    echo "       or run: scripts/tick-lock.sh release" >&2
    echo "       (TICK_LOCK_STALE_MINUTES raises the threshold if your ticks are longer.)" >&2
    return 2
  fi

  echo "HELD: a tick is in flight — $LOCK, taken $(human_age "$age") ago by $ag ($ts)." >&2
  return 1
}

case "$cmd" in
  acquire)
    # THE CHECK AND THE WRITE, IN ONE `O_EXCL` CREATE. Nothing runs between them because
    # there is no "between" — this is the whole reason the script exists rather than a
    # `[ -f ] && write` in the launcher's prose.
    if ( set -o noclobber
         printf '%s\n' \
           "# ai-bridge PM tick lock. Written by /pm-loop immediately before it dispatches a tick." \
           "# PER CLONE and gitignored — NOT a cross-machine lock: two clones of one shared" \
           "# bundle each have their own, and each dispatches independently by design." \
           "# Stale after ${STALE_MINUTES}m (TICK_LOCK_STALE_MINUTES). Clear it with:" \
           "#   scripts/tick-lock.sh release" \
           "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           "epoch: $NOW" \
           "agent: $agent" > "$LOCK"
       ) 2>/dev/null; then
      exit 0   # Silence is the contract: the human ran a command, not a briefing.
    fi

    # The create failed. Either something holds the lock, or this root cannot be written —
    # and those are different answers, so they are not collapsed into one.
    if [ ! -e "$LOCK" ]; then
      echo "tick-lock: cannot write $LOCK — the instance root is not writable." >&2
      echo "           Refusing to dispatch: a lock nothing can write is a guarantee" >&2
      echo "           nothing is keeping, and that is the failure this replaces." >&2
      exit 3
    fi
    judge_existing; exit $?
    ;;

  release)
    # Absence is a silent success, not an error — releasing a lock nobody holds is the
    # normal outcome of a loop that was interrupted, and it must never scroll or fail.
    [ -e "$LOCK" ] || exit 0
    rm -f "$LOCK" 2>/dev/null && exit 0
    echo "tick-lock: could not remove $LOCK" >&2
    exit 3
    ;;

  status)
    # READ-ONLY, AND NOT FOR THE LAUNCHER. This is the human's (and the harness's) probe.
    # A launcher that called `status` and then `acquire` would have re-created the
    # check-then-write window that `acquire` exists to close.
    if [ ! -e "$LOCK" ]; then
      echo "free: no $LOCK — the next /pm-loop dispatch takes it."
      exit 0
    fi
    judge_existing; exit $?
    ;;
esac
