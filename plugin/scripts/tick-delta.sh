#!/usr/bin/env bash
#
# tick-delta.sh — the idle-tick fast-path probe: can this tick skip the full walk?
#
#   Usage: tick-delta.sh check  [--instance DIR] [--gap TEXT]
#          tick-delta.sh record [--instance DIR]
#          tick-delta.sh record --close TEXT [--tick ISO] [--tokens N] [--tools N] [--duration-ms N]
#          tick-delta.sh digest [--instance DIR]
#
# `record --close TEXT` IS THE LEDGER HALF, AND IT TOUCHES NO FINGERPRINT. It appends
# `* TICK <ts> <by> close: TEXT` BESIDE the tick's own open line rather than rewriting it,
# so the pair at one timestamp is the tick's wall duration. The three usage flags append
# the one fixed form `agent-usage.sh fmt` prints; without them the line closes exactly as
# it always did. Offline — no git, no gh — and a second close for one tick is refused.
# `--tick <ISO>` names WHICH entry to close, matched exactly; without it a close is taken
# only when exactly one entry is open. Two racing ticks are refused, never guessed —
# guessing closes the other tick's entry under your summary and leaves yours open.
#
# WHY THIS EXISTS. A tick re-derives everything every time — full task walk, a live
# read of every open PR — which is correct and stays the default. But measured on a
# live instance (2026-08-27), three CONSECUTIVE zero-delta ticks each did the whole
# walk at full depth on the dearest model tier, to conclude "nothing changed". The
# comparison that proves "nothing changed" needs no model at all: it is a fingerprint
# a shell can take and diff. So a FULL tick records what it saw (`record`, its last
# act), and the next tick asks first (`check`) — the model ingests one verdict line
# instead of re-reading a world that did not move.
#
# THE PROBE CAN ONLY EVER SKIP WORK IT PROVES UN-OWED. Every doubt — no record yet, no
# `gh`, an unreadable file, a probe error — is exit 2, and exit 2 means the full tick
# runs. The optimisation fails toward the behaviour that was always correct, never
# away from it. And exit 0 is not a licence to skip the LOCK or the LEDGER: the tick's
# step 0/0.5 run before this is consulted, every tick.
#
# WHAT THE FINGERPRINT HOLDS, and why each line is in it:
#
#   head <sha>              the bundle HEAD — a commit from the other human, a folded
#                           answer, a promotion: all move it (step 0 pulled first).
#   dirty/untracked         ANY tracked change, or an untracked file under projects/,
#                           is an immediate DELTA before fingerprinting — a human
#                           mid-edit (an appended answer is exactly this) or a sibling
#                           mid-write is never an idle tick.
#   task <path> <status>    every task's status — a move to/from any status is a delta,
#                           and any `in-progress` task is an immediate DELTA whatever
#                           the record says: a live dispatch is owed its monitoring.
#   pr <url> <state> <head> <decision>
#                           every PR on an `in-review` task, from the host: a pushed
#                           head, a merge, a close, or a review decision each require
#                           tick work (re-verify, reflect, or send back).
#   queue/snapshot <present|absent>
#                           the two opt-in artifacts' presence — `touch AWAITING.md`
#                           re-enables the queue and needs one full tick to populate.
#
# WHAT IT DELIBERATELY DOES NOT SEE, stated rather than discovered: a PR body edit at
# an unchanged head (an unticked box, an edited description) and anything visible only
# in comment prose. Those defer to the next real delta — the same trade the yolo merge
# gate refuses (it re-reads at the moment of merging) but a GATED surface-only tick can
# afford, because nothing is merged on the strength of an idle verdict.
#
# `digest` IS THE SAME WALK, ENRICHED, FOR THE TICK THAT MUST NOW ORIENT. One command
# prints every live project (slug, status, autonomy, owner), every task under them
# (path, status, kind, assignee, dependency/open-question counts, criteria filled or
# not, worktree recorded or not) and every open PR's host facts — so step 1's N
# frontmatter reads and per-PR `gh` round-trips become one read. It changes NOTHING
# about what the tick may act on: the digest is the enumeration, never the judgement,
# and the tick still opens every document it acts on. A `status: done` project is
# skipped at its frontmatter in BOTH walks, exactly as the tick and write-snapshot.sh
# already skip it — nothing in a done project can need a tick.
#
# Exit codes — only 0 permits the fast path, and it is never the default:
#   0  IDLE — matches the record; prints ONE `IDLE:` line, which IS the quiet tick's
#      whole report, so it names the next check (`--gap`, else "the next tick").
#   1  DELTA — something moved; prints `DELTA:` lines naming what. Full tick.
#   2  cannot answer — no record, no `gh`, not a git repo, probe error. Full tick.
#   3  usage.
#
# `record` writes `.tick-state` (gitignored, per clone — the same class as
# `.tick-lock`) and refuses (exit 2, file untouched) when it cannot compute the full
# fingerprint: a partial record would turn the next check's "match" into a lie.
#
# GENERIC PLUGIN FILE — ships inside the `ai-bridge` plugin; no org, repo or path literals.
# Verified by tests/tick-delta.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

STATE_NAME="$AB_STATE_DIR"

usage() {
  echo "Usage: $(basename "$0") check|record|digest [--instance DIR] [--gap TEXT]" >&2
  echo "       $(basename "$0") record --close TEXT [--tick ISO] [--tokens N] [--tools N] [--duration-ms N]" >&2
  exit 3
}

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in check|record|digest) ;; *) usage ;; esac

inst="."
gap=""
close=""; close_set=0; tick=""; tokens=""; tools=""; ms=""
while [ $# -gt 0 ]; do
  case "$1" in
    --close|--tick|--tokens|--tools|--duration-ms)
      [ "$cmd" = record ] || { echo "tick-delta: $1 is a \`record\` flag" >&2; exit 3; }
      [ $# -ge 2 ] || { echo "tick-delta: $1 needs a value" >&2; exit 3; }
      case "$1" in
        # The FLAG decides the path, never its value: `--close ""` is a usage error.
        --close)       close="$2"; close_set=1 ;;
        --tick)        tick="$2" ;;
        --tokens)      tokens="$2" ;;
        --tools)       tools="$2" ;;
        --duration-ms) ms="$2" ;;
      esac
      shift 2 ;;
    --instance)
      [ $# -ge 2 ] || { echo "tick-delta: --instance needs a directory" >&2; exit 3; }
      inst="$2"; shift 2 ;;
    --gap)
      [ $# -ge 2 ] || { echo "tick-delta: --gap needs an interval, e.g. 10m" >&2; exit 3; }
      # Alnum only: the IDLE line is the whole report, so nothing may add a line to it.
      case "$2" in *[![:alnum:]]*|"") echo "tick-delta: --gap takes an interval like 10m" >&2; exit 3 ;; esac
      gap="$2"; shift 2 ;;
    *) usage ;;
  esac
done
next_check="on the next tick"
[ -n "$gap" ] && next_check="in $gap"
[ -d "$inst" ] || { echo "tick-delta: no such instance directory: $inst" >&2; exit 2; }
ab_ensure_dir "$inst"
STATE="$inst/$STATE_NAME"

fail2() { echo "CANNOT ANSWER: $1 — run the full tick." >&2; exit 2; }

# --- the ledger half ---------------------------------------------------------------------
# Beside the open line, never over it. Everything here is file reads and one insert: a tick
# that cannot reach git or gh must still be able to close its own entry.
if [ "$close_set" -eq 0 ] && { [ -n "$tick" ] || [ -n "$tokens" ] || [ -n "$tools" ] || [ -n "$ms" ]; }; then
  echo "tick-delta: the usage flags go on --close, so they need one" >&2; exit 3
fi
if [ "$close_set" -eq 1 ]; then
  LOG="$inst/$AB_LEDGER"
  [ -f "$LOG" ] && [ -w "$LOG" ] || fail2 "no writable $LOG"
  close="$(printf '%s' "$close" | tr '\n\t' '  ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
  case "$close" in
    '') echo "tick-delta: --close needs a summary" >&2; exit 3 ;;
    *"~/"*) echo "REFUSED: a ledger line carries no path under \`~\` — rewrite the summary." >&2; exit 1 ;;
  esac
  # Whichever marker comes FIRST decides the line. A summary is free prose and may quote
  # the other word, so a plain substring test misfiles the entry it is reading.
  found="$(WANT="$tick" awk '
    /^\* TICK / {
      o = index($0, " open: "); c = index($0, " close: ")
      if (c > 0 && (o == 0 || c < o)) { closed[$3] = 1; next }
      if (o > 0) { n++; ts[n] = $3; at[n] = NR }
    }
    END {
      want = ENVIRON["WANT"]
      for (i = n; i >= 1; i--) {
        if (ts[i] in closed) continue
        if (want != "" && ts[i] != want) continue
        if (++open_n == 1) hit = at[i] " " ts[i]
      }
      if (open_n > 1)  { print "AMBIGUOUS"; exit }
      if (open_n == 1) { print hit; exit }
      print (n > 0 ? (want != "" ? "NOMATCH" : "CLOSED") : "NOOPEN")
    }
  ' "$LOG")" || fail2 "could not read $LOG"
  case "$found" in
    NOOPEN) echo "REFUSED: no \`open:\` TICK entry in $LOG." >&2; exit 1 ;;
    CLOSED) echo "REFUSED: every open TICK entry already carries a close — not double-writing." >&2; exit 1 ;;
    NOMATCH) echo "REFUSED: no open TICK entry at \`$tick\` in $LOG — it is already closed, or was never opened." >&2; exit 1 ;;
    AMBIGUOUS) echo "REFUSED: $LOG has more than one open TICK entry — pass \`--tick <the timestamp of the open line you wrote>\`; closing the newest could close another tick's entry." >&2; exit 1 ;;
  esac
  at="${found%% *}"; ts="${found#* }"
  by="$(sed -n "${at}p" "$LOG")"; by="${by#\* TICK "$ts"}"; by="${by%% open:*}"
  FMT="$(dirname "$0")/agent-usage.sh"
  [ -x "$FMT" ] || { echo "tick-delta: $FMT is missing — the one usage form lives there." >&2; exit 2; }
  suffix="$("$FMT" fmt --tokens "$tokens" --tools "$tools" --duration-ms "$ms")" \
    || { echo "tick-delta: $FMT could not format the usage numbers." >&2; exit 2; }
  line="* TICK $ts$by close: $close"
  [ "$suffix" = "usage UNKNOWN" ] || line="$line · $suffix"
  tmp="$LOG.close.$$"
  AT="$at" LINE="$line" awk 'NR == ENVIRON["AT"] + 0 { print; print ENVIRON["LINE"]; next } { print }' \
    "$LOG" > "$tmp" || { rm -f "$tmp"; fail2 "cannot write beside $LOG"; }
  [ -s "$tmp" ] || { rm -f "$tmp"; fail2 "refusing to replace $LOG with an empty file"; }
  mv "$tmp" "$LOG" || { rm -f "$tmp"; fail2 "cannot replace $LOG"; }
  echo "closed: $ts"
  exit 0
fi

command -v git >/dev/null 2>&1 || fail2 "git not found"
git -C "$inst" rev-parse --verify -q HEAD >/dev/null 2>&1 || fail2 "not a git repo (or no commits)"

# --- immediate deltas: a tree anyone is mid-editing is never idle -----------------------
# These are checked before any fingerprint, because they are deltas the RECORD can never
# legitimately contain: a full tick ends with its own work committed.
if [ "$cmd" = check ]; then
  # The status reads FAIL CLOSED: a `git status` that errors must not read as "clean" —
  # an empty answer and no answer point in opposite directions here.
  dirty="$(git -C "$inst" status --porcelain --untracked-files=no 2>/dev/null)"     || fail2 "git status failed — the tree cannot be judged"
  if [ -n "$dirty" ]; then
    echo "DELTA: tracked files are dirty — someone is mid-edit (an appended answer looks exactly like this)."
    exit 1
  fi
  untracked="$(git -C "$inst" status --porcelain -- projects 2>/dev/null)"     || fail2 "git status failed — the tree cannot be judged"
  untracked="$(printf '%s\n' "$untracked" | grep '^??' || true)"
  if [ -n "$untracked" ]; then
    echo "DELTA: untracked file(s) under projects/ — a draft in the making."
    exit 1
  fi
fi

# --- the walk ---------------------------------------------------------------------------
# One line per fact, deterministic order. The PROBE lines are the fingerprint —
# comparison is line-for-line, so a mismatch can NAME what moved. The DIGEST is the same
# walk with the enrichment the orienting tick needs; the two share one traversal so they
# cannot drift about which documents exist.

fmfirst() { # <file> <key> — the first `key:`'s scalar value
  sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" "$1" | head -n1
}
# Entries in a `key: [ ... ]` block (inline or multi-line): lines that carry content
# once brackets and blanks are stripped. A count, because that is all a digest needs.
fmcount() { # <file> <key>
  sed -n "/^$2:/,/\]/p" "$1" | sed -e "s/^$2:[[:space:]]*//" -e 's/[][]//g'     | grep -c '[^[:space:]]' || true
}

fingerprint() { # <probe|digest>
  local mode="$1"
  printf 'head %s\n' "$(git -C "$inst" rev-parse HEAD)"

  [ -f "$inst/$AB_AWAITING" ]   && printf 'queue present\n'    || printf 'queue absent\n'
  [ -f "$inst/$AB_SNAPSHOT" ] && printf 'snapshot present\n' || printf 'snapshot absent\n'

  local p d pst f st prs url inflight=0 urls=""
  for d in "$inst"/projects/*/; do
    [ -d "$d" ] || continue
    p="$d/project.md"
    # A project directory whose project.md is missing or unreadable poisons the walk —
    # its tasks would otherwise silently vanish from the fingerprint, which is the
    # false-IDLE hole this script must never open. (validate-bundle owns the schema
    # error; this probe just refuses to guess around it.)
    [ -f "$p" ] && [ -r "$p" ] || return 1
    pst="$(fmfirst "$p" status)"; pst="${pst:-unset}"
    if [ "$mode" = digest ]; then
      printf 'project %s status=%s autonomy=%s owner=%s\n'         "$(basename "$(dirname "$p")")" "$pst"         "$(fmfirst "$p" autonomy | grep -oE '^[A-Za-z-]+' || printf -- -)"         "$(fmfirst "$p" owner    | grep -oE '^[A-Za-z0-9._-]+' || printf -- -)"
    fi
    # A done project is skipped at its FRONTMATTER, in both walks — the same rule the
    # tick and write-snapshot.sh already apply: nothing in a done project can need a
    # tick, and the point is the read that never happens.
    [ "$pst" = done ] && continue

    for f in "$d"tasks/*.md; do
      [ -f "$f" ] || continue
      # An UNREADABLE task file poisons the whole walk rather than degrading to a fake
      # `unset` fact — a record built on a hole would let the next check "match" it.
      [ -r "$f" ] || return 1
      st="$(sed -n 's/^status:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$f" | head -n1)"
      if [ "$mode" = digest ]; then
        printf 'task %s status=%s kind=%s assignee=%s deps=%s q=%s crit=%s wt=%s\n'           "${f#"$inst"/}" "${st:-unset}"           "$(fmfirst "$f" kind | grep -oE '^[A-Za-z-]+' || printf -- -)"           "$(fmfirst "$f" assignee | grep -oE '^[A-Za-z0-9._-]+' || printf -- -)"           "$(fmcount "$f" depends_on)" "$(fmcount "$f" open_questions)"           "$([ "$(fmcount "$f" acceptance_criteria)" -gt 0 ] && echo yes || echo no)"           "$([ -n "$(fmfirst "$f" worktree)" ] && echo yes || echo no)"
      else
        printf 'task %s %s\n' "${f#"$inst"/}" "${st:-unset}"
      fi
      [ "$st" = "in-progress" ] && inflight=1
      if [ "$st" = "in-review" ]; then
        prs="$(grep -m1 '^pr:' "$f" 2>/dev/null | grep -oE 'https://[^"[:space:]]+/pull/[0-9]+' || true)"
        [ -n "$prs" ] && urls="$urls
$prs"
      fi
    done
  done

  # A live dispatch is owed its monitoring whatever the record says. Signalled as a
  # fingerprint line so `record` captures it too, and short-circuited in `check` below.
  [ "$inflight" = 1 ] && printf 'inflight yes\n' || printf 'inflight no\n'

  # Every open-PR fact comes from the HOST, via gh's own --jq (no local jq needed). A
  # failure on any one PR poisons the whole fingerprint — better no answer than a match
  # built on a hole.
  local u line
  for u in $(printf '%s\n' "$urls" | grep . | sort -u); do
    command -v gh >/dev/null 2>&1 || return 1
    line="$(gh pr view "$u" --json state,headRefOid,reviewDecision \
            --jq '[.state, .headRefOid, (.reviewDecision // "NONE")] | join(" ")' 2>/dev/null)" || return 1
    case "$line" in
      *" "*" "*) printf 'pr %s %s\n' "$u" "$line" ;;
      *) return 1 ;;
    esac
  done
  return 0
}

mode=probe; [ "$cmd" = digest ] && mode=digest
FP="$(fingerprint "$mode")" || fail2 "could not complete the fingerprint (an unreadable task file, gh missing or offline, or a bad PR URL)"

case "$cmd" in
  digest)
    # The enumeration for an orienting tick, nothing more: no record is read or written,
    # and printing it grants nothing — the tick still opens every document it acts on.
    printf '%s\n' "$FP"
    exit 0
    ;;
  record)
    # Through a temp file BESIDE the target: a crash mid-write must not leave a torn
    # record for the next check to "match".
    tmp="$STATE.tmp.$$"
    {
      printf '# tick-delta fingerprint — written by tick-delta.sh record at the END\n'
      printf '# of a FULL tick. Read by `check` on the next tick; a byte-for-byte match is\n'
      printf '# the idle fast-path. Gitignored, per clone. Delete freely: absence = full tick.\n'
      printf 'recorded: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '%s\n' "$FP"
    } > "$tmp" || { rm -f "$tmp" 2>/dev/null; fail2 "cannot write $STATE"; }
    mv "$tmp" "$STATE" || { rm -f "$tmp" 2>/dev/null; fail2 "cannot write $STATE"; }
    exit 0
    ;;
  check)
    if printf '%s\n' "$FP" | grep -qx 'inflight yes'; then
      echo "DELTA: task(s) in-progress — a live dispatch is owed its monitoring."
      exit 1
    fi
    [ -f "$STATE" ] || fail2 "no $STATE_NAME record yet (first tick, or an upgrade)"
    OLD="$(grep -v '^#' "$STATE" | grep -v '^recorded:' || true)"
    [ -n "$OLD" ] || fail2 "$STATE_NAME is empty or unreadable"
    if [ "$FP" = "$OLD" ]; then
      # Reported verbatim as the whole tick, so it names the next check — else a human
      # cannot tell a quiet loop from a stopped one.
      echo "IDLE: fingerprint unchanged since $(sed -n 's/^recorded: //p' "$STATE" | head -n1) — nothing moved; next check $next_check."
      exit 0
    fi
    echo "DELTA: the fingerprint moved —"
    # Named, not just detected: the full tick re-derives everything anyway, so these
    # lines are a hint for the report, never the orientation.
    diff <(printf '%s\n' "$OLD") <(printf '%s\n' "$FP") 2>/dev/null \
      | grep '^[<>]' | sed -e 's/^</  was: /' -e 's/^>/  now: /' | head -20
    exit 1
    ;;
esac
