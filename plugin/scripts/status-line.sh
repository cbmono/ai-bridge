#!/usr/bin/env bash
#
# status-line.sh — one line for Claude Code's `statusLine`: what is in flight, what waits
# on the human, whether a tick holds the lock, when the last tick was.
#
#   status-line.sh [--instance DIR] [--color auto|always|never]
#
# A script, never a model: file reads, no `gh`, no network, no `jq`. Any JSON Claude Code
# puts on stdin is drained and only read for the session's directory.
# Exit: 0 always (a status line never fails a session), 3 usage.
# Reasoning: ai-bridge-v3/task-025.
set -uo pipefail

INST=""; COLOR=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) shift; INST="${1:-}"; shift || true ;;
    --instance=*) INST="${1#--instance=}"; shift ;;
    --color) shift; COLOR="${1:-auto}"; shift || true ;;
    --color=*) COLOR="${1#--color=}"; shift ;;
    -h|--help) sed -n '2,10p' "$0" >&2; exit 3 ;;
    *) echo "status-line: unknown option: $1" >&2; exit 3 ;;
  esac
done
case "$COLOR" in auto|always|never) ;; *) echo "status-line: --color takes auto|always|never" >&2; exit 3 ;; esac

# Claude Code writes the session JSON here. Draining it is not optional — an unread pipe
# is a SIGPIPE on the writer's next line.
STDIN=""
[ -t 0 ] || STDIN="$(cat 2>/dev/null || true)"

json_str() { printf '%s' "$STDIN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }

if [ -z "$INST" ]; then
  INST="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$INST" ] || INST="$(json_str current_dir)"
  [ -n "$INST" ] || INST="$(json_str cwd)"
  [ -n "$INST" ] || INST="$PWD"
fi

# The bundle marker is `instance.config.json`, the same one session-banner.sh keys on.
# Walked up from the session's directory, because a session is as often in a subdirectory.
root=""
d="$INST"
for _ in 1 2 3 4 5 6 7 8; do
  [ -n "$d" ] && [ "$d" != "/" ] || break
  if [ -f "$d/instance.config.json" ]; then root="$d"; break; fi
  d="$(dirname "$d")"
done
# Outside a bundle this prints nothing at all rather than an error or an empty frame.
[ -n "$root" ] || exit 0

# COLOUR IS ON UNDER A BARE NON-TTY, AND THAT IS THE WHOLE POINT OF THIS BLOCK. A
# `statusLine` command's stdout is ALWAYS a pipe into Claude Code, which renders the SGR
# itself — so `[ -t 1 ]` would strip the colour off the one surface that must carry it.
# `NO_COLOR` and `--color never` are the opt-outs, exactly as everywhere else here.
# 3/4-bit only: `COLORTERM` and `tput colors` are not reliably inherited by a process
# Claude Code spawns, and no state below needs more than eight colours.
use_color=0
case "$COLOR" in
  always) use_color=1 ;;
  never)  use_color=0 ;;
  *)      [ -z "${NO_COLOR:-}" ] && use_color=1 ;;
esac
C_B=""; C_DIM=""; C_RED=""; C_YEL=""; C_CYA=""; C_OFF=""
if [ "$use_color" -eq 1 ]; then
  esc="$(printf '\033')"
  C_B="${esc}[1m"; C_DIM="${esc}[2m"; C_RED="${esc}[31m"
  C_YEL="${esc}[33m"; C_CYA="${esc}[36m"; C_OFF="${esc}[0m"
fi
paint() { printf '%s%s%s' "$1" "$2" "$C_OFF"; }

UNKNOWN='?'

# --- in flight: the task frontmatter, directly ------------------------------------------
# Not SNAPSHOT.json: its absence is the BOARD's off switch, and it carries in-flight only
# as a per-task boolean. One awk pass, first frontmatter block of each task document.
inflight="$UNKNOWN"
if [ -d "$root/projects" ]; then
  set -- "$root"/projects/*/tasks/*.md
  if [ -e "$1" ]; then
    inflight="$(awk '
      FNR == 1 { fm = 0; hit = 0; if ($0 == "---") { fm = 1; next } }
      fm && $0 == "---" { fm = 0; next }
      fm && !hit && $0 ~ /^status:[[:space:]]*in-progress[[:space:]]*$/ { n++; hit = 1 }
      END { print n + 0 }
    ' "$@" 2>/dev/null)" || inflight="$UNKNOWN"
    [ -n "$inflight" ] || inflight="$UNKNOWN"
  else
    inflight=0
  fi
fi

# --- need you: AWAITING.md's own items, counted the way the banner counts them -----------
# Deletable by design, so absent is NOT zero — nothing can be established about the queue
# from a file that is not there.
awaiting="$UNKNOWN"
if [ -r "$root/AWAITING.md" ]; then
  awaiting="$(awk '
    /^##[[:space:]].*Awaiting you/ { inblk = 1; next }
    inblk && /^##[[:space:]]/      { exit }
    inblk && /^[[:space:]]*\* /    { n++ }
    END { print n + 0 }
  ' "$root/AWAITING.md" 2>/dev/null)" || awaiting="$UNKNOWN"
  [ -n "$awaiting" ] || awaiting="$UNKNOWN"
fi

# --- the lock: one `[ -f ]`, never a call into tick-lock.sh ------------------------------
lock=free
[ -f "$root/.tick-lock" ] && lock=held

# --- last tick: log.md's last `* TICK` line ---------------------------------------------
# NOT `.tick-state`: tick-delta.sh refuses to stamp it while any task is in-progress, so it
# is guaranteed stale exactly while `in flight` is non-zero. An `open:` line counts — a tick
# that started and has not closed is still the last tick.
last="$UNKNOWN"
if [ -r "$root/log.md" ]; then
  ts="$(awk '/^\* TICK [0-9][0-9][0-9][0-9]-[0-9][0-9]-/ { t = $3 } END { print t }' \
        "$root/log.md" 2>/dev/null)"
  if [ -n "$ts" ]; then
    # The stamp is UTC and the reader is not. BSD first — it needs `-u` on the PARSE and a
    # second call to print local, and GNU `date` has no `-j` to be confused by.
    ep="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null)" || ep=""
    if [ -n "$ep" ]; then hm="$(date -r "$ep" '+%H:%M' 2>/dev/null)" || hm=""
    else                  hm="$(date -d "$ts" '+%H:%M' 2>/dev/null)" || hm=""; fi
    [ -n "$hm" ] && last="$hm"
  fi
fi

n_colour() { case "$1" in "$UNKNOWN") printf '%s' "$C_RED" ;; 0) printf '%s' "$C_DIM" ;; *) printf '%s' "$2" ;; esac; }
SEP="$(paint "$C_DIM" ' · ')"

printf '%s' "$(paint "$C_B" 'AI Bridge')"
printf '%s%s' "$SEP" "$(paint "$(n_colour "$inflight" "$C_CYA")" "$inflight in flight")"
printf '%s%s' "$SEP" "$(paint "$(n_colour "$awaiting" "$C_YEL")" "$awaiting need you")"
if [ "$lock" = held ]; then printf '%s%s' "$SEP" "$(paint "$C_YEL" 'lock held')"
else                        printf '%s%s' "$SEP" "$(paint "$C_DIM" 'lock free')"; fi
if [ "$last" = "$UNKNOWN" ]; then printf '%s%s\n' "$SEP" "$(paint "$C_RED" "last tick $UNKNOWN")"
else                              printf '%s%s\n' "$SEP" "$(paint "$C_DIM" "last tick $last")"; fi
exit 0
