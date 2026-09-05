#!/usr/bin/env bash
#
# watch-board.sh — keep a LOCAL board page up to date: render the HTML board into a
# gitignored directory, then re-render whenever a task document changes.
#
#   Usage:
#     scripts/watch-board.sh [--out DIR] [--interval SECS] [--once] [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render and watch. With none given, the list
#                       comes from `boardInstances` in ./instance.config.local.json,
#                       else ./instance.config.json; if that key is absent or empty,
#                       just this instance. Resolved by `build-board.sh
#                       --list-instances`, so there is exactly one discovery rule.
#     --out DIR         where the page goes (default: ./.board-live). Gitignored.
#     --interval SECS   polling interval when there is no fswatch (default: 2).
#     --once            render once and exit. No watching, nothing to interrupt.
#
# THE COST, STATED FIRST, BECAUSE IT IS THE REASON TO PICK A DIFFERENT RENDERER.
# THIS NEEDS A RESIDENT PROCESS, AND ai-bridge DELIBERATELY DOES NOT HAVE ONE. Its
# agents are ephemeral subagents inside one Claude Code session; nothing here runs
# between sessions, and no daemon is installed or supervised. That is the same
# constraint that made munder-difflin's live telemetry unreachable for us. So this is
# a terminal tab you keep open, and it stops the moment you close it, sleep the
# machine, or lose the session. In exchange you get a page that is live to the second
# and never leaves the machine. Weigh it against the other two:
#
#   · scripts/print-board.sh  — one shot, in the terminal you are already in. No
#     process, no browser, no file. Reach for this by default.
#   · scripts/build-board.sh  — one shot, an HTML page you can publish and read on a
#     phone. No process either, but the page is only as fresh as the last run.
#   · this                    — live, local-only, per-machine, and it costs a process.
#
# WHAT IT ACTUALLY DOES, PER CYCLE. Refresh THIS instance's snapshot (so the page
# reflects the documents rather than the last /pm-loop tick), then run
# `build-board.sh --standalone` over every watched instance. It adds no renderer of its
# own and no HTML of its own: forking the board's markup would mean two pages to keep
# escaping correctly, and escaping untrusted titles is the one thing that page must
# never get wrong.
#
# IT WRITES INSIDE THIS INSTANCE ONLY, AND THAT LINE IS DELIBERATE. An earlier version
# ran the writer in every watched directory, which meant a watcher started in one group
# rewrote another group's SNAPSHOT.json every couple of seconds — a file that group's
# own loop owns. So: the writer runs here, and a sibling instance is rendered from
# whatever snapshot it currently has. That is honestly less live for the siblings, and
# it is the trade: their snapshots are refreshed by their own /pm-loop tick (or their
# own watcher), and when one of them changes THIS page re-renders, because a watched
# instance's SNAPSHOT.json is part of the trigger set below.
#
# ABSENCE IS THE OFF SWITCH, UNTOUCHED. An instance with no SNAPSHOT.json is skipped
# by the writer (it never creates one) and left off the page by the renderer. This
# script never creates one either, so `rm SNAPSHOT.json` still means "off the board".
#
# SELF-DETECTING. Outside an instance root (no SCHEMA.md + instance.config.json) it
# exits 0 having printed nothing at all — it ships into every instance and will be run
# from the wrong directory.
#
# WATCHING: PROBE, THEN DEGRADE TO A DECLARED FALLBACK. `fswatch` is not installed
# everywhere and is not installable everywhere, so it is probed, never assumed:
#   · fswatch present → `fswatch --one-event` blocks until something changes under a
#     watched path. Sub-second, no busy work.
#   · fswatch absent  → a polling loop with a `--interval` default of 2 seconds. Plain
#     `find`, so it works on any machine this ships to.
# `WATCH_BOARD_WATCHER` overrides the probe: `poll` forces the fallback (useful when a
# machine's fswatch misbehaves, and the only way a test can exercise the poll path on a
# machine that HAS fswatch), `fswatch` asks for it explicitly but still falls back with
# a message rather than failing, and the default `auto` probes. Same role SNAPSHOT_NOW
# plays for write-snapshot.sh: a knob that exists so the behaviour is reachable.
# EITHER WAY the decision to re-render is made by the same mtime check, never by the
# notifier: fswatch reports events we do not care about (a `.DS_Store`, an editor swap
# file), and the check is what makes the two mechanisms behave identically. The check
# also runs immediately after every render, so a write that lands DURING a render is
# not lost waiting for the next event.
#
# The output directory is deliberately NOT inside any watched path, so the page's own
# write cannot trigger the next render. Keep it that way if you change --out.
#
# INTERRUPTIBLE, AND IT LEAVES NOTHING BEHIND. Every wait runs its command in the
# background and `wait`s on it, because bash defers a trap until a foreground child
# exits — so a foreground `sleep 2` would swallow your Ctrl-C for up to two seconds,
# and a foreground `fswatch` would swallow it until the next file change, which may be
# never. On INT/TERM the child is killed, the mtime stamp file is removed, and the exit
# status is 0: stopping a watcher is not a failure. The rendered page is left in place
# on purpose — it is the product, and it is gitignored.
#
# Deterministic apart from the "rendered HH:MM:SS" progress line — the page itself is
# build-board.sh's output, unchanged. No network. Verified by
# tests/board-renderers.test.sh.
set -euo pipefail

OUT_DIR=".board-live"
INTERVAL=2
ONCE=0
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "watch-board: --out needs a path" >&2; exit 2; }; OUT_DIR="$1" ;;
    --out=*) OUT_DIR="${1#--out=}" ;;
    --interval) shift; [[ $# -gt 0 ]] || { echo "watch-board: --interval needs a number" >&2; exit 2; }; INTERVAL="$1" ;;
    --interval=*) INTERVAL="${1#--interval=}" ;;
    --once) ONCE=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "watch-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done
case "$INTERVAL" in ''|*[!0-9]*|0) echo "watch-board: --interval takes a positive integer" >&2; exit 2 ;; esac
# Validated HERE, with the flags, rather than beside the probe that uses it — a --once
# run exits before the probe, and an unknown value accepted there is a refusal that
# only fires on the path nobody tested.
case "${WATCH_BOARD_WATCHER:-auto}" in auto|poll|fswatch) ;; *) echo "watch-board: WATCH_BOARD_WATCHER takes auto|poll|fswatch" >&2; exit 2 ;; esac
[[ -n "$OUT_DIR" ]] || { echo "watch-board: --out needs a path" >&2; exit 2; }

# Self-detecting, and silent when it does not apply — see the header.
[[ -f SCHEMA.md && -f instance.config.json ]] || exit 0

# The sibling scripts, found relative to THIS file so it works from the template and
# from an instance (where both are symlinks in the same scripts/ directory).
HERE="$(cd "$(dirname "$0")" && pwd)"
BOARD="$HERE/build-board.sh"
WRITER="$HERE/write-snapshot.sh"
for f in "$BOARD" "$WRITER"; do
  [[ -f "$f" ]] || { echo "watch-board: missing $f" >&2; exit 2; }
done

# Discovery is build-board.sh's job, asked rather than reimplemented: named dirs, else
# `boardInstances` (in instance.config.local.json, else instance.config.json), else —
# when the key is absent or empty — just this instance. Never a glob.
WATCH_DIRS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  WATCH_DIRS+=("$line")
done < <(bash "$BOARD" --list-instances "${DIRS[@]+"${DIRS[@]}"}" 2>/dev/null || true)
[[ ${#WATCH_DIRS[@]} -gt 0 ]] || { echo "watch-board: no instance resolved — nothing to watch." >&2; exit 0; }

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/board.html"
STAMP="$OUT_DIR/.watch-stamp"

# THE TRIGGER SET, in two parts:
#   · every markdown document under THIS instance's projects/ — the schema-defined
#     location the snapshot is derived from, and the only input the refresh below reads;
#   · every watched instance's SNAPSHOT.json, so a sibling group's own /pm-loop tick
#     shows up on this page too, without this script writing in their directory.
DOC_DIRS=()
[[ -d "./projects" ]] && DOC_DIRS+=("./projects")
SNAP_FILES=()
for d in "${WATCH_DIRS[@]}"; do
  [[ -f "$d/SNAPSHOT.json" ]] && SNAP_FILES+=("$d/SNAPSHOT.json")
done
# What fswatch is pointed at: this instance's documents, plus each OTHER watched
# instance (a snapshot is replaced by a rename, so the directory is the reliable thing
# to watch, not the file). Extra wakeups are harmless — changed() below is what decides
# whether anything is re-rendered, which is also what keeps the two mechanisms
# behaving identically.
FS_TARGETS=("${DOC_DIRS[@]+"${DOC_DIRS[@]}"}")
for d in "${WATCH_DIRS[@]}"; do
  [[ -d "$d" && "$(cd "$d" 2>/dev/null && pwd)" != "$PWD" ]] && FS_TARGETS+=("$d")
done

doc_list() {
  [[ ${#DOC_DIRS[@]} -gt 0 ]] || return 0
  find "${DOC_DIRS[@]}" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
}

LAST_LIST=""

# Two questions, because mtime alone cannot see a deletion: is anything NEWER than the
# stamp, and has the SET of documents changed? A rename answers the first, a delete
# only the second.
changed() {
  [[ -e "$STAMP" ]] || return 0
  local now newer
  if [[ ${#DOC_DIRS[@]} -gt 0 ]]; then
    newer="$(find "${DOC_DIRS[@]}" -type f -name '*.md' -newer "$STAMP" 2>/dev/null | head -1)"
    [[ -n "$newer" ]] && return 0
  fi
  if [[ ${#SNAP_FILES[@]} -gt 0 ]]; then
    newer="$(find "${SNAP_FILES[@]}" -maxdepth 0 -newer "$STAMP" 2>/dev/null | head -1)"
    [[ -n "$newer" ]] && return 0
  fi
  now="$(doc_list)"
  [[ "$now" != "$LAST_LIST" ]] && return 0
  return 1
}

render() {
  # The stamp is touched BEFORE the work, never after: a document written while the
  # render is in flight then has an mtime newer than the stamp and is caught on the
  # next check. Touching it afterwards would date the stamp past that write and lose
  # it silently, which is the false-freshness bug this whole file exists to avoid.
  : > "$STAMP"
  LAST_LIST="$(doc_list)"
  # This instance only — see the header. The off switch is honoured exactly as the
  # writer honours it: no SNAPSHOT.json here means this instance opted out, so nothing
  # is written and nothing is created, and the page is built from whoever else has one.
  if [[ -f "SNAPSHOT.json" ]]; then
    bash "$WRITER" --quiet || echo "watch-board: write-snapshot failed — rendering the previous snapshot." >&2
  fi
  if ! bash "$BOARD" --standalone --out "$OUT_FILE" "${WATCH_DIRS[@]}" >/dev/null; then
    echo "watch-board: build-board failed — the page was not updated." >&2
    return 0
  fi
  printf '%s  rendered %s\n' "$(date +%H:%M:%S)" "$OUT_FILE"
}

CHILD=""
cleanup() {
  [[ -n "$CHILD" ]] && kill "$CHILD" 2>/dev/null || true
  CHILD=""
  rm -f "$STAMP"
}
# Stopping a watcher is not a failure, so INT and TERM exit 0. EXIT covers every other
# way out (an error under `set -e`, a closed terminal) so the stamp never survives.
trap 'cleanup; echo "watch-board: stopped. The page is still at $OUT_FILE."; exit 0' INT TERM
trap 'cleanup' EXIT

# Run a blocking command in the background and wait on it, so a trap fires at once
# rather than after the child returns. See the header.
run_wait() {
  "$@" >/dev/null 2>&1 &
  CHILD=$!
  wait "$CHILD" 2>/dev/null || true
  CHILD=""
}

render

if [[ $ONCE -eq 1 ]]; then
  exit 0
fi

WANT="${WATCH_BOARD_WATCHER:-auto}"
MECH="poll"
WHY=""
if [[ ${#FS_TARGETS[@]} -eq 0 ]]; then
  WHY="nothing to watch yet (no projects/ directory here) — polling every ${INTERVAL}s for one to appear."
elif [[ "$WANT" == poll ]]; then
  WHY="polling ${#FS_TARGETS[@]} path(s) every ${INTERVAL}s (WATCH_BOARD_WATCHER=poll). Ctrl-C to stop."
elif command -v fswatch >/dev/null 2>&1; then
  MECH="fswatch"
  WHY="watching ${#FS_TARGETS[@]} path(s) with fswatch. Ctrl-C to stop."
elif [[ "$WANT" == fswatch ]]; then
  WHY="fswatch was asked for but is not installed — polling ${#FS_TARGETS[@]} path(s) every ${INTERVAL}s. Ctrl-C to stop."
else
  WHY="fswatch not found — polling ${#FS_TARGETS[@]} path(s) every ${INTERVAL}s. Ctrl-C to stop."
fi
echo "watch-board: $WHY"
echo "watch-board: open $OUT_FILE in a browser and reload it after each 'rendered' line."

while :; do
  if changed; then
    render
    # Re-check ONCE, so a write that landed during the render is picked up now rather
    # than waiting for the next event or interval — and once only, deliberately. A
    # document whose mtime is in the future (a clock-skewed checkout, an unzipped
    # archive) is newer than every stamp forever, and an unbounded re-check would spin
    # on it, burning a core for as long as the watcher runs.
    if changed; then render; fi
  fi
  if [[ "$MECH" == fswatch ]]; then
    run_wait fswatch --one-event --recursive "${FS_TARGETS[@]}"
  else
    run_wait sleep "$INTERVAL"
  fi
done
