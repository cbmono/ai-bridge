#!/usr/bin/env bash
#
# board-renderers.test.sh — the two renderers added over the SAME snapshot the HTML
# board already reads: scripts/print-board.sh (terminal) and scripts/watch-board.sh
# (a local page kept fresh by a watcher). tests/snapshot.test.sh owns the writer and
# the HTML renderer; this file owns everything that is new.
#
# The properties that matter are the negative ones, in this order:
#   · THE OFF SWITCH IS INHERITED, NOT REIMPLEMENTED. No SNAPSHOT.json ⇒ that instance
#     is absent from the terminal board and from the live page, and NEITHER renderer
#     creates one. A renderer that resurrected the file would quietly undo
#     "delete it to take this instance off the board", which is the one promise the
#     whole feature rests on.
#   · A DRIFTED INSTANCE CANNOT BLANK THE BOARD. Valid JSON with wrong TYPES
#     (`"tasks": "many"`) is the case that already broke this once: a bare int() raised
#     before any output was produced, so one drifted instance took every healthy one
#     down with it. Each case asserts BOTH halves — this instance degrades AND the
#     healthy instance beside it still renders. A fix that dropped every instance would
#     pass the first half alone.
#   · UNTRUSTED TEXT REACHES A TERMINAL, WHICH HAS ITS OWN METACHARACTERS AND THEY ARE
#     WORSE THAN HTML'S. A title carrying ESC would clear the screen or repaint what
#     the reader has already read; a title carrying a newline would forge a row, so the
#     board would REPORT WORK THAT DOES NOT EXIST; a tab would forge a column; a bidi
#     override would reorder the line. Titles are human prose, so all four are asserted
#     as absent, and the payload is asserted present as inert text — stripped, not
#     silently dropped.
#   · COLOUR IS A TTY PROPERTY. Piped output must contain no escape byte at all, or
#     every board redirected into a file, a PR body or a ticket is corrupted. The
#     positive direction is asserted too (`--color always` DOES emit one), because
#     "no escapes" alone would pass a script that printed nothing.
#   · NUMBERS NEVER TRUNCATE. A clipped count is a WRONG number, which is worse than a
#     missing one, so narrowing drops whole all-zero columns and clips NAMES.
#   · THE WATCHER IS INTERRUPTIBLE AND LEAVES NOTHING BEHIND. Exit 0 on a signal, no
#     stamp file, no orphaned child. A watcher you cannot stop cleanly is a watcher
#     nobody starts.
#   · THE LIVE PAGE IS GITIGNORED, checked against git's own answer rather than the
#     pattern text — and on an instance whose .gitignore predates the line, which is
#     every instance that exists today.
#
# The fixture builds its own instances under mktemp, so these assertions describe this
# test's content and not whatever the real bundles hold. The hostile snapshots are
# HAND-WRITTEN on purpose: the writer cannot emit an ESC (it strips C0), and each
# renderer's defence has to hold independently of the writer's.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
WRITER="$TPL/symlink/scripts/write-snapshot.sh"
BOARD="$TPL/symlink/scripts/build-board.sh"
PRINT="$TPL/symlink/scripts/print-board.sh"
WATCH="$TPL/symlink/scripts/watch-board.sh"
BRIDGE_INSTALL="$TPL/install.sh"
for f in "$WRITER" "$BOARD" "$PRINT" "$WATCH" "$BRIDGE_INSTALL"; do
  [[ -f "$f" ]] || { echo "board-renderers.test: missing $f" >&2; exit 2; }
done
# Both renderers reach the same python3 the HTML board already requires (see
# build-board.sh's header for why JSON parsing and escaping are not awk's job). A
# machine without it cannot run the board at all, so say so rather than reporting green
# on half a feature.
command -v python3 >/dev/null 2>&1 || {
  echo "board-renderers.test: needs python3 (the board does too — see build-board.sh)." >&2; exit 2; }

# TWO STEPS, NEVER ONE — the one-expression form is DESTRUCTIVE. When $TMPDIR names a
# directory that does not exist, `mktemp -d` fails, the inner substitution of
# `TMP="$(cd "$(mktemp -d …)" && pwd)"` is empty, `cd ""` SUCCEEDS WITHOUT MOVING (a
# documented bash no-op), `pwd` returns this script's own cwd — the checkout — and the
# trap below deletes it. That happened twice on 2026-08-23. So the creation is guarded
# here, and the normalisation below is handed a path already known good.
# tests/harness-temp-safety.test.sh fails on the one-expression form anywhere in tests/.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-renderers.XXXXXX")" || {
  echo "board-renderers.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# cd+pwd normalises the path: TMPDIR carries a trailing slash on macOS, so the raw
# mktemp result contains `//`, and a path assertion then matches nothing either way.
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { printf '%s\n' "$2" | grep -qF -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -qF -- "$1" && echo 1 || echo 0; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }
# The longest line, in CHARACTERS. awk's length() counts BYTES on macOS and this output
# is full of multibyte punctuation (·, ›, —, …), so an awk version of this check reports
# a correctly-fitted table as overflowing.
maxlen() { printf '%s\n' "$1" | python3 -c 'import sys; print(max((len(l) for l in sys.stdin.read().splitlines()), default=0))'; }
fits()   { [[ "$(maxlen "$1")" -le "$2" ]] && echo 0 || echo 1; }

ESC="$(printf '\033')"

# ---------------------------------------------------------------- fixture
new_instance() { # <dir> — the minimum both renderers require of an instance root
  mkdir -p "$1"
  : > "$1/SCHEMA.md"
  cat > "$1/instance.config.json" <<CFG
{ "org": "fixture-org", "reposRoot": "$TMP/repos" }
CFG
}

ALPHA="$TMP/group/_ai-bridge-alpha"     # real content, written by the writer
BETA="$TMP/group/_ai-bridge-beta"       # unparseable snapshot
GAMMA="$TMP/group/_ai-bridge-gamma"     # no snapshot at all — off the board
DELTA="$TMP/group/_ai-bridge-delta"     # hand-written hostile snapshot
new_instance "$ALPHA"; new_instance "$BETA"; new_instance "$GAMMA"; new_instance "$DELTA"

mkdir -p "$ALPHA/projects/ci/tasks" "$ALPHA/projects/ci/phases"
cat > "$ALPHA/projects/ci/project.md" <<'PRJ'
---
type: Project
title: CI hardening
kind: build
status: active
---
PRJ
cat > "$ALPHA/projects/ci/phases/phase-1.md" <<'PH'
---
type: Phase
title: Groundwork
order: 1
status: done
---
PH
cat > "$ALPHA/projects/ci/phases/phase-2.md" <<'PH'
---
type: Phase
title: Rollout
order: 2
status: active
---
PH
cat > "$ALPHA/projects/ci/tasks/task-001.md" <<'TSK'
---
type: Task
title: Rotate the publish token
kind: build
status: blocked
assignee: devops-engineer
---
TSK
cat > "$ALPHA/projects/ci/tasks/task-002.md" <<'TSK'
---
type: Task
title: Bump the pinned toolchain
kind: build
status: in-review
assignee: software-engineer
pr: [ "https://github.com/acme/monorepo/pull/2725" ]
---
TSK
cat > "$ALPHA/projects/ci/tasks/task-003.md" <<'TSK'
---
type: Task
title: Cache the dependency store
kind: build
status: in-progress
assignee: software-engineer
---
TSK
# A very long title, for the clipping assertions. Long enough that no sane terminal
# width leaves it intact, so "piped output is never clipped" is a real assertion.
mkdir -p "$ALPHA/projects/verbose/tasks"
cat > "$ALPHA/projects/verbose/project.md" <<'PRJ'
---
type: Project
title: LONGTITLE-a-deliberately-overlong-project-name-that-no-terminal-width-leaves-intact-END
kind: build
status: active
---
PRJ

touch "$ALPHA/SNAPSHOT.json"
( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-23T00:00:00Z bash "$WRITER" --quiet )

printf '{ this is not json' > "$BETA/SNAPSHOT.json"

# The hostile snapshot, written through json.dump so every escape is unambiguous. Each
# attack gets its OWN project, so one table row per attack and a forged row is visible
# as a row that does not begin with the instance name.
python3 - "$DELTA/SNAPSHOT.json" <<'PY'
import json, sys

def proj(slug, title, status="ready"):
    return {"slug": slug, "title": title, "kind": "build", "status": "active",
            "autonomy": "gated", "awaiting_close": False,
            "phase_progress": {"done": 0, "total": 0}, "phases": [],
            "tasks": [{"id": "task-001", "title": "t", "kind": "build",
                       "status": status, "assignee": "software-engineer", "phase": "",
                       "in_flight": False, "awaiting": "", "open_questions": 0,
                       "prs": []}]}

snap = {
    "group": "delta",
    "generated_at": "2026-08-23T00:00:00Z",
    "counts": {"projects": 5, "tasks": 5, "awaiting": 1},
    "projects": [
        # ESC: a clear-screen and a colour change, both of which must arrive inert.
        proj("ansi", "ANSITITLE\u001b[2J\u001b[31mPAYLOAD"),
        # A newline would forge a whole row — the board reporting work nobody has.
        proj("newline", "ROWA\nFORGEDROW"),
        # A tab would forge a column inside a row.
        proj("tab", "COLA\tCOLB"),
        # A right-to-left override reorders the line a reader is trying to trust.
        proj("bidi", "BIDIA‮BIDIB"),
        # A status outside the schema enum: counted under OTHER and named, never
        # silently dropped.
        proj("drifted", "DRIFTEDSTATUS", status="made-up-status"),
    ],
}
snap["projects"][0]["tasks"][0]["awaiting"] = "merge"
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(snap, fh)
PY

echo "== print-board: self-detecting, and silent where it does not apply =="
mkdir -p "$TMP/stranger"
S_OUT="$( cd "$TMP/stranger" && bash "$PRINT" 2>&1 )"; S_RC=$?
assert "outside an instance root -> exits 0"        "$(eq "$S_RC" 0)"
assert "…and prints absolutely nothing"             "$(eq "$S_OUT" "")"
assert "…and creates no file there"                 "$(no_if test -e "$TMP/stranger/SNAPSHOT.json")"

echo
echo "== print-board: bad flags refuse rather than guess =="
for bad in --nope --width=x --color=purple; do
  RC=0; OUT="$( cd "$ALPHA" && bash "$PRINT" "$bad" 2>&1 >/dev/null )" || RC=$?
  assert "'$bad' exits 2"           "$(eq "$RC" 2)"
  assert "…and says so on stderr"   "$(no_if test -z "$OUT")"
done

echo
echo "== print-board: the off switch, and a broken instance cannot blank the board =="
OUT="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$BETA" "$GAMMA" "$DELTA" 2>"$TMP/pb.err" )"; RC=$?
ERR="$(cat "$TMP/pb.err")"
assert "exits 0 with a malformed snapshot in the list" "$(eq "$RC" 0)"
assert "the healthy instance renders"                  "$(has 'CI hardening' "$OUT")"
assert "…and so does the hostile one beside it"        "$(has 'delta' "$OUT")"
assert "gamma has no snapshot, so it is absent"        "$(hasnt 'gamma' "$OUT")"
assert "…and the reason is on stderr, not on the board" "$(has 'off the board' "$ERR")"
assert "beta is a VISIBLE note, not a silent absence"  "$(has 'unreadable SNAPSHOT.json' "$OUT")"
assert "…naming the instance by directory NAME"        "$(has '_ai-bridge-beta' "$OUT")"
assert "…and not by its path"                          "$(hasnt '/_ai-bridge-beta' "$OUT")"
assert "…telling the human what to re-run"             "$(has 'write-snapshot.sh' "$OUT")"
assert "no filesystem path reaches the output"         "$(hasnt "$TMP" "$OUT")"
assert "neither renderer created gamma's snapshot"     "$(no_if test -e "$GAMMA/SNAPSHOT.json")"
assert "an out-of-enum status is counted under OTHER"  "$(has 'OTHER' "$OUT")"
assert "…and named, so drift is visible"               "$(has 'made-up-status' "$OUT")"

echo
echo "== print-board: untrusted text at a TERMINAL sink =="
assert "ZERO escape bytes in the output"        "$(hasnt "$ESC" "$OUT")"
assert "an ESC title arrives as inert text"     "$(has 'ANSITITLE[2J[31mPAYLOAD' "$OUT")"
# A forged row would be a line that does not start with the instance name. Asserting
# the two halves land on the SAME line is what proves the newline could not split it.
FORGED_LINE="$(printf '%s\n' "$OUT" | grep -F 'FORGEDROW' || true)"
assert "a newline in a title cannot forge a row" "$(has 'ROWA FORGEDROW' "$FORGED_LINE")"
assert "…and that row still starts with the instance" "$(yes_if sh -c 'printf "%s" "$1" | grep -q "^delta "' _ "$FORGED_LINE")"
assert "a tab in a title cannot forge a column"  "$(has 'COLA COLB' "$OUT")"
assert "…and no tab survives into the output"    "$(hasnt "$(printf '\t')" "$OUT")"
assert "a bidi override is stripped"             "$(hasnt "$(printf '\342\200\256')" "$OUT")"
assert "…and its text survives around it"        "$(has 'BIDIABIDIB' "$OUT")"
# One row per project, counted off the instance column: a forged row would make six.
assert "delta renders exactly 5 rows, one per project" \
  "$(eq "$(printf '%s\n' "$OUT" | grep -c '^delta ' || true)" 5)"

echo
echo "== print-board: colour is a TTY property =="
assert "piped output carries no escape byte" "$(hasnt "$ESC" "$( cd "$ALPHA" && bash "$PRINT" 2>/dev/null )")"
# The positive direction, so the assertion above cannot pass on a script that prints
# nothing: forced colour DOES emit one.
assert "--color always does emit one"        "$(has "$ESC" "$( cd "$ALPHA" && bash "$PRINT" --color always 2>/dev/null )")"
assert "--no-color suppresses it again"      "$(hasnt "$ESC" "$( cd "$ALPHA" && bash "$PRINT" --color always --no-color 2>/dev/null )")"
# NO_COLOR can only be observed with a real TTY, since a pipe is already colourless.
# The pty comes from python3's stdlib rather than script(1): script's arguments differ
# between BSD and GNU, and whether it can allocate a terminal at all depends on how this
# harness was launched — which made the assertion COUNT drift between runs. python3 is
# already a hard requirement of the board, so this costs nothing and always runs.
tty_out() { # <cmd...> -> the command's output, with its stdout on a real terminal
  ( cd "$ALPHA" && python3 -c 'import pty,sys; sys.exit(pty.spawn(sys.argv[1:]))' "$@" 2>/dev/null )
}
assert "on a TTY, colour is on by default" "$(has "$ESC" "$(tty_out bash "$PRINT" --width 100)")"
assert "…and NO_COLOR turns it off"        "$(hasnt "$ESC" "$(NO_COLOR=1 tty_out bash "$PRINT" --width 100)")"
assert "…while NO_COLOR= (empty) does not" "$(has "$ESC" "$(NO_COLOR= tty_out bash "$PRINT" --width 100)")"
assert "…and --color always beats NO_COLOR, as documented" \
  "$(has "$ESC" "$(NO_COLOR=1 tty_out bash "$PRINT" --color always --width 100)")"

echo
echo "== print-board: a narrow terminal degrades, and no NUMBER is ever clipped =="
WIDE="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" 2>/dev/null )"
assert "unlimited width prints the table"          "$(has 'INSTANCE  PROJECT' "$WIDE")"
assert "…with every enum column"                   "$(yes_if sh -c 'printf "%s" "$1" | grep -q "DRAFT READY PROG REVIEW BLOCK DONE CANC"' _ "$WIDE")"
assert "…and an unclipped long title (a pipe is not narrow)" "$(has 'LONGTITLE-a-deliberately-overlong-project-name-that-no-terminal-width-leaves-intact-END' "$WIDE")"
N80="$( cd "$ALPHA" && bash "$PRINT" --width 80 "$ALPHA" 2>/dev/null )"
assert "at 80 columns it is still a table"         "$(has 'INSTANCE' "$N80")"
assert "…no line exceeds the width"                "$(fits "$N80" 80)"
assert "…the long title is clipped with an ellipsis" "$(has '…' "$N80")"
assert "…all-zero columns are dropped to make room" "$(has 'omitted to fit the width' "$N80")"
assert "…a column that was dropped had a zero total" "$(hasnt 'CANC' "$N80")"
assert "…AWAIT is never dropped"                    "$(has 'AWAIT' "$N80")"
# The counts must be identical at every width: dropping a zero column hides nothing,
# and a clipped number would be a wrong number.
# Every non-zero number on a row must survive narrowing unchanged. Dropping a column
# of zeros hides no work; clipping a count would report a WRONG number, and the two are
# indistinguishable on the page unless something compares them.
nonzero() { printf '%s\n' "$1" | grep -F 'CI hardening' | grep -oE '[0-9]+' | grep -v '^0$' | tr '\n' ' '; }
assert "every non-zero count survives narrowing unchanged" "$(eq "$(nonzero "$N80")" "$(nonzero "$WIDE")")"
assert "…and there was something to compare"               "$(no_if test -z "$(nonzero "$WIDE")")"
NARROW="$( cd "$ALPHA" && bash "$PRINT" --width 34 "$ALPHA" 2>/dev/null )"
assert "below the table's minimum it becomes a list" "$(hasnt 'INSTANCE' "$NARROW")"
assert "…with a labelled block per project"          "$(has 'phases' "$NARROW")"
# The property is the full enum name rather than the table's abbreviation ("REVIEW").
# Not "in-review 1": the block wraps at the width, so the name and its count can
# legitimately land on different lines, and asserting the pair makes the test fail for
# a formatting reason that has nothing to do with the property.
assert "…naming statuses in full, not as column headers" "$(has 'in-review' "$NARROW")"
assert "…and not the abbreviation"                       "$(hasnt 'REVIEW' "$NARROW")"
assert "…and no line exceeds the width"              "$(fits "$NARROW" 34)"

echo
echo "== print-board: a drifted snapshot cannot blank the board =="
# THE MAJOR CASE. Valid JSON, wrong TYPES — the malformed path above never sees these,
# and a bare int() would raise before a single line was printed, taking the healthy
# instance down too. Both halves are asserted for every case.
DRIFT="$TMP/group/_ai-bridge-drift"
mkdir -p "$DRIFT"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$DRIFT/SNAPSHOT.json"
  local rc=0 out
  out="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$DRIFT" 2>&1 )" || rc=$?
  assert "$1: exits 0"                            "$(eq "$rc" 0)"
  assert "$1: no traceback"                        "$(hasnt 'Traceback' "$out")"
  assert "$1: something was printed"               "$(has 'Bridge Board' "$out")"
  assert "$1: the healthy instance still renders"  "$(has 'CI hardening' "$out")"
}
drift_case "a non-numeric task count" \
  '{"group":"drift","counts":{"tasks":"many","projects":1,"awaiting":0},"projects":[]}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"phases":[],"tasks":[]}]}'
drift_case "a non-string group" \
  '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":"t","title":"T","status":"blocked","awaiting":"unblock","open_questions":0,"prs":[]}]}]}'
drift_case "projects is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":"lots"}'
drift_case "tasks is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":"three"}]}'
drift_case "a task is a string, not an object" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":["oops"]}]}'
# ANCHORED to the instance column: a bare `has 5` would pass on any board, since the
# counts alone print plenty of digits.
printf '%s\n' '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[]}]}' > "$DRIFT/SNAPSHOT.json"
D5="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$DRIFT" 2>/dev/null )"
assert "a non-string group becomes the row's instance cell" \
  "$(yes_if sh -c 'printf "%s\n" "$1" | grep -q "^5  *Drifted"' _ "$D5")"
rm -rf "$DRIFT"

echo
echo "== discovery is explicit, never a glob (both new scripts ask build-board) =="
D1="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "no args, no boardInstances -> just this instance" "$(has '1 instance(s)' "$D1")"
assert "…and the output says where the list came from"    "$(has 'this instance' "$D1")"
python3 - "$ALPHA/instance.config.json" "$DELTA" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["boardInstances"] = [".", sys.argv[2]]
json.dump(d, open(p, "w"), indent=2)
PY
D2="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "boardInstances is used when no dirs are named"    "$(has '2 instance(s)' "$D2")"
assert "…and is named as the source"                      "$(has 'boardInstances' "$D2")"
assert "named dirs override the config"                   "$(has '1 instance(s)' "$( cd "$ALPHA" && bash "$PRINT" "$DELTA" 2>&1 )")"
LIST="$( cd "$ALPHA" && bash "$BOARD" --list-instances 2>/dev/null )"
assert "--list-instances resolves the same two"           "$(eq "$(printf '%s\n' "$LIST" | grep -c . )" 2)"
assert "…as paths, one per line"                          "$(has "$DELTA" "$LIST")"
assert "…and writes no board file"                        "$(no_if test -e "$ALPHA/board.html")"
LIST2="$( cd "$ALPHA" && bash "$BOARD" --list-instances "$GAMMA" 2>/dev/null )"
assert "…and named dirs still win there"                  "$(eq "$LIST2" "$GAMMA")"
printf 'not json at all' > "$ALPHA/instance.config.json"
D3="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "an unreadable config falls back to this instance"  "$(has '1 instance(s)' "$D3")"
assert "…and says so"                                      "$(has 'unreadable' "$D3")"
assert "…with no traceback"                                "$(hasnt 'Traceback' "$D3")"
for shape in '["a","b"]' '"just-a-string"' '5' 'null' 'true'; do
  printf '%s\n' "$shape" > "$ALPHA/instance.config.json"
  RC=0; OUT2="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )" || RC=$?
  assert "a config whose top level is $shape falls back, exit 0" "$(eq "$RC" 0)"
  assert "…rendering just this instance"  "$(has '1 instance(s)' "$OUT2")"
  assert "…with no traceback"             "$(hasnt 'Traceback' "$OUT2")"
done
new_instance "$ALPHA"   # restore a clean config

echo
echo "== watch-board: self-detecting, and silent where it does not apply =="
W_OUT="$( cd "$TMP/stranger" && bash "$WATCH" --once 2>&1 )"; W_RC=$?
assert "outside an instance root -> exits 0"  "$(eq "$W_RC" 0)"
assert "…and prints absolutely nothing"       "$(eq "$W_OUT" "")"
assert "…and creates no output directory"     "$(no_if test -e "$TMP/stranger/.board-live")"
for bad in --nope --interval=0 --interval=x; do
  RC=0; ( cd "$ALPHA" && bash "$WATCH" "$bad" >/dev/null 2>&1 ) || RC=$?
  assert "'$bad' exits 2" "$(eq "$RC" 2)"
done

echo
echo "== watch-board --once: one render, into a gitignored directory =="
O_OUT="$( cd "$ALPHA" && bash "$WATCH" --once "$ALPHA" "$BETA" "$GAMMA" 2>&1 )"; O_RC=$?
PAGE="$ALPHA/.board-live/board.html"
assert "exits 0"                                  "$(eq "$O_RC" 0)"
assert "…and says what it rendered"               "$(has 'rendered' "$O_OUT")"
assert "the page is written"                      "$(yes_if test -s "$PAGE")"
assert "…as a standalone document, openable directly" "$(yes_if sh -c 'head -1 "$1" | grep -qF "<!doctype html>"' _ "$PAGE")"
assert "…rendering the healthy instance"          "$(fhas 'CI hardening' "$PAGE")"
assert "…and the malformed one as a visible note" "$(fhas 'Unreadable snapshot' "$PAGE")"
assert "an instance with no snapshot is absent"   "$(fhasnt '_ai-bridge-gamma' "$PAGE")"
assert "…and its snapshot was NOT created"        "$(no_if test -e "$GAMMA/SNAPSHOT.json")"
assert "the mtime stamp is cleaned up"            "$(no_if test -e "$ALPHA/.board-live/.watch-stamp")"
assert "nothing else is left in the output dir"   "$(eq "$(ls -A "$ALPHA/.board-live" | grep -c . )" 1)"
# It refreshes the snapshot before rendering, so the page reflects the DOCUMENTS rather
# than the last /pm-loop tick. A new task must appear without running the writer.
cat > "$ALPHA/projects/ci/tasks/task-004.md" <<'TSK'
---
type: Task
title: NEWTASK-added-since-the-last-snapshot
kind: build
status: ready
---
TSK
( cd "$ALPHA" && bash "$WATCH" --once "$ALPHA" >/dev/null 2>&1 )
assert "--once refreshes the snapshot first"      "$(fhas 'NEWTASK-added-since-the-last-snapshot' "$PAGE")"
# The terminal board is project-level — task TITLES never appear on it, only counts —
# so the refreshed snapshot shows up as a task total, and that is what to assert.
assert "…and the terminal board counts it too"   "$(has '4 task(s)' "$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" 2>/dev/null )")"

echo
echo "== watch-board: the watch mechanism is probed, and degrades to a declared poll =="
# No `timeout` here: it is GNU coreutils and absent from a stock macOS, which is the
# machine this suite is run on. Start the watcher in the background, let it announce
# itself, then signal it — which also exercises the interrupt path a second time.
STUBDIR="$TMP/stub"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/fswatch" <<'STUB'
#!/bin/sh
# Stand-in for fswatch: block until killed. The watcher's fswatch branch is then
# exercised on a machine that does not have the real binary — which is most of them,
# and precisely why the fallback exists.
while :; do sleep 1; done
STUB
chmod +x "$STUBDIR/fswatch"
# Poll for a NEEDLE rather than sleeping a guessed duration — see `briefly` below for
# why a fixed sleep here was the actual defect, not a machine-dependent one. Ceiling of
# 200 * 0.05s = 10s so a genuinely broken watcher still fails in finite time instead of
# hanging; a healthy one resolves in well under a second.
wait_for() { # <file> <needle> [max-tries]
  local file="$1" needle="$2" tries="${3:-200}" n=0
  while (( n < tries )); do
    grep -qF -- "$needle" "$file" 2>/dev/null && return 0
    sleep 0.05
    n=$((n+1))
  done
  return 1
}
briefly() { # <env-prefix...> -- run the watcher until it announces itself, then stop it
  local log="$TMP/briefly.log"; : > "$log"
  # `exec`, so the background job IS the watcher and a TERM reaches it rather than the
  # subshell that spawned it. Getting this wrong makes the signal assertions pass for
  # the wrong reason — the subshell dies, the watcher is orphaned, and its exit status
  # is never read.
  ( cd "$ALPHA" && exec env "$@" bash "$WATCH" --interval 1 "$ALPHA" ) >"$log" 2>&1 &
  local p=$!
  # This used to be a fixed `sleep 2`, racing the initial render — a real subprocess
  # chain (write-snapshot.sh, then build-board.sh) whose duration is host- and
  # load-dependent, not a constant. Under load the message below hadn't been printed
  # yet when the 2s elapsed, and every assertion reading $log came back empty. The
  # announcement line is printed on EVERY branch (poll, fswatch, or the fswatch-asked-
  # for-but-absent fallback) right after the mechanism is decided, so waiting for it
  # is the actual event to wait for rather than a guess at how long it takes.
  wait_for "$log" "in a browser and reload it" 200 || true
  kill -TERM "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  cat "$log"
}
POLL_MSG="$(briefly WATCH_BOARD_WATCHER=poll)"
assert "forced polling says so, and how often"               "$(has 'polling 1 path(s) every 1s' "$POLL_MSG")"
FS_MSG="$(briefly WATCH_BOARD_WATCHER=auto PATH="$STUBDIR:$PATH")"
assert "with fswatch on PATH the probe picks it"             "$(has 'with fswatch' "$FS_MSG")"
assert "…and does not claim to be polling"                   "$(hasnt 'polling' "$FS_MSG")"
assert "…and it still stops cleanly"                         "$(has 'stopped. The page is still at' "$FS_MSG")"
assert "…leaving no fswatch child behind"                    "$(no_if pgrep -f "$STUBDIR/fswatch")"
FS_ASK="$(briefly WATCH_BOARD_WATCHER=fswatch PATH="/usr/bin:/bin")"
assert "asking for an absent fswatch falls back, saying why" "$(has 'asked for but is not installed' "$FS_ASK")"
# Forced absent via PATH, same as the FS_ASK case above — never asked of the host with a
# bare `command -v fswatch`. This used to skip itself on any machine that happens to have
# fswatch installed, which means the "auto, no fswatch" branch went completely untested
# on exactly the runners most likely to have it (a dev laptop with it brewed in). Both
# branches must run everywhere, or CI coverage depends on which machine picks up the job.
assert "the bare probe on a machine without fswatch polls" \
  "$(has 'fswatch not found' "$(briefly WATCH_BOARD_WATCHER=auto PATH="/usr/bin:/bin")")"
RC=0; ( cd "$ALPHA" && WATCH_BOARD_WATCHER=nonsense bash "$WATCH" --once >/dev/null 2>&1 ) || RC=$?
assert "an unknown WATCH_BOARD_WATCHER refuses rather than guessing" "$(eq "$RC" 2)"


echo
echo "== watch-board: it re-renders on a change, and stops cleanly =="
rm -rf "$ALPHA/.board-live"
# `exec` again: the background job must BE the watcher, or `wait` below reads the
# subshell's status instead of the watcher's and the exit-0-on-TERM assertion is vacuous.
( cd "$ALPHA" && exec bash "$WATCH" --interval 1 "$ALPHA" ) >"$TMP/watch.log" 2>&1 &
WPID=$!
# Same defect as `briefly` above, same fix: wait for the render to actually land in the
# log instead of a fixed sleep racing it. A `sleep 2` here is exactly the assertion below
# it — "has rendered once already" — turned into a guess about how long that takes.
wait_for "$TMP/watch.log" "rendered" 200 || true
assert "the watcher is running"                 "$(yes_if kill -0 "$WPID")"
assert "…and has rendered once already"         "$(fhas 'rendered' "$TMP/watch.log")"
assert "…leaving its stamp file in place"       "$(yes_if test -e "$ALPHA/.board-live/.watch-stamp")"
BEFORE="$(grep -c 'rendered' "$TMP/watch.log" || true)"
cat > "$ALPHA/projects/ci/tasks/task-005.md" <<'TSK'
---
type: Task
title: WATCHED-CHANGE-appeared-while-watching
kind: build
status: ready
---
TSK
sleep 4
AFTER="$(grep -c 'rendered' "$TMP/watch.log" || true)"
assert "a task-document write triggers a re-render" "$(yes_if test "$AFTER" -gt "$BEFORE")"
assert "…and the change is on the page"             "$(fhas 'WATCHED-CHANGE-appeared-while-watching' "$PAGE")"
kill -TERM "$WPID" 2>/dev/null || true
WRC=0; wait "$WPID" 2>/dev/null || WRC=$?
assert "a TERM exits 0 — stopping a watcher is not a failure" "$(eq "$WRC" 0)"
assert "…saying the page is still there"            "$(fhas 'stopped. The page is still at' "$TMP/watch.log")"
assert "…removing its stamp file"                   "$(no_if test -e "$ALPHA/.board-live/.watch-stamp")"
assert "…leaving the page it produced"              "$(yes_if test -s "$PAGE")"
assert "…and no child process behind it"            "$(no_if pgrep -P "$WPID" )"

echo
echo "== the live page is gitignored — git's own answer, not the pattern text =="
assert "seed/.gitignore ignores the live directory" "$(yes_if grep -qF '.board-live' "$TPL/seed/.gitignore")"
INST="$TMP/group/_ai-bridge-stamped"
mkdir -p "$INST"
( cd "$INST" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1 </dev/null
mkdir -p "$INST/.board-live" && : > "$INST/.board-live/board.html" && : > "$INST/.board-live/probe.txt"
assert "a FRESH stamp ignores the page" \
  "$(yes_if git -C "$INST" check-ignore -q .board-live/board.html)"
# The probe file, not board.html: the seed carries a bare `board.html` line that matches
# at ANY depth, so board.html inside the directory is ignored either way and cannot show
# whether the DIRECTORY line is present. A test that cannot fail is worse than none.
assert "…and the whole directory, not just the page" \
  "$(yes_if git -C "$INST" check-ignore -q .board-live/probe.txt)"
# The case that actually matters: every instance in existence was stamped before this
# directory existed, so the line has to reach an OLD .gitignore too.
OLD="$TMP/group/_ai-bridge-old"
mkdir -p "$OLD"
( cd "$OLD" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1 </dev/null
python3 - "$OLD/.gitignore" <<'PY'
import sys
p = sys.argv[1]
keep = [l for l in open(p).read().splitlines() if ".board-live" not in l]
open(p, "w").write("\n".join(keep) + "\n")
PY
mkdir -p "$OLD/.board-live" && : > "$OLD/.board-live/probe.txt"
assert "…and with the line removed, git no longer ignores it" \
  "$(no_if git -C "$OLD" check-ignore -q .board-live/probe.txt)"
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1 </dev/null
assert "…a re-run of install.sh puts it back"  "$(yes_if git -C "$OLD" check-ignore -q .board-live/probe.txt)"
assert "…exactly once, not once per run"       "$(eq "$(grep -cF '.board-live' "$OLD/.gitignore")" 1)"
echo
echo "== a fresh instance is named by its directory, not \".\" =="
# install.sh seeds a snapshot with an EMPTY group, and the default discovery target is
# Path("."), whose .name is empty too — so both renderers fell through and labelled the
# instance ".". Asserted here for BOTH of them, even though tests/snapshot.test.sh owns
# the HTML board otherwise: the fallback is shared, and it was fixed in one change.
FRESH_TTY="$( cd "$INST" && bash "$PRINT" --width 0 2>/dev/null )"
assert "the terminal board names the instance"     "$(yes_if sh -c 'printf "%s\n" "$1" | grep -q "^stamped "' _ "$FRESH_TTY")"
assert "…and never labels a row \".\""              "$(yes_if sh -c 'printf "%s\n" "$1" | grep -qv "^\. "' _ "$FRESH_TTY")"
( cd "$INST" && bash "$BOARD" --out "$TMP/fresh.html" >/dev/null 2>&1 )
# The HTML board puts the name in its masthead, title-cased ("stamped" -> "Stamped").
# The "." bug shows there as a LEADING SPACE, not as a dot: the title is built from
# `group.split(".")[0]`, so a group of "." would title the page " Bridge Board" — which
# looks like a stray space and reads as no instance name at all. Both halves are
# asserted, because either alone passes on the other's failure.
assert "the HTML board names it too"                "$(fhas '<h1>Stamped Bridge Board</h1>' "$TMP/fresh.html")"
assert "…and never an empty name in the masthead"   "$(fhasnt '<h1> Bridge Board' "$TMP/fresh.html")"

# The renderers must be linked into an instance, or nobody can run them there.
assert "install.sh links print-board.sh"       "$(yes_if test -L "$INST/scripts/print-board.sh")"
assert "…and watch-board.sh"                   "$(yes_if test -L "$INST/scripts/watch-board.sh")"
assert "…and both resolve"                     "$(yes_if sh -c 'test -f "$1/scripts/print-board.sh" && test -f "$1/scripts/watch-board.sh"' _ "$INST")"

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
