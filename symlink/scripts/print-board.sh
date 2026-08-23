#!/usr/bin/env bash
#
# print-board.sh — print the cross-instance board in the TERMINAL: one row per
# project, with columns for instance, project, phase progress, tasks by status, and
# the awaiting count.
#
#   Usage:
#     scripts/print-board.sh [--width N] [--color auto|always|never] [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to print. With none given, the list comes from
#                       `boardInstances` in ./instance.config.local.json, else
#                       ./instance.config.json; if that key is absent or empty, just
#                       this instance.
#     --width N         pin the layout width in columns (default: the terminal's when
#                       stdout is a TTY, else unlimited). `--width 0` = unlimited.
#     --color WHEN      `auto` (default) colours only a TTY and only when NO_COLOR is
#                       unset or empty; `never` never does; `always` forces it, NO_COLOR
#                       included — an explicit flag beats an environment preference.
#     --no-color        the same as `--color never`.
#
# THE THIRD RENDERER OVER THE SAME SNAPSHOT, AND WHY THAT IS THE WHOLE POINT.
# `write-snapshot.sh` derives SNAPSHOT.json; `build-board.sh` renders it as an HTML
# page you may publish; this prints it as columns for someone already in a terminal.
# No publish step, no browser, no resident process. It reads ONLY the snapshot — never
# the bundle — because the snapshot is the observation contract, including the field
# allowlist that decides what may leave an instance at all. Do not re-derive anything
# here, and do not add a field to the writer to feed this.
#
# ABSENCE IS THE OFF SWITCH. An instance with no SNAPSHOT.json does not appear — no
# placeholder, no warning (the run says so on stderr, where it costs a human nothing).
# This script never creates one. See write-snapshot.sh for why that is permanent.
#
# SELF-DETECTING. Outside an instance root (no SCHEMA.md + instance.config.json) it
# exits 0 having printed nothing at all, like the SessionStart hooks: the same reason
# they do it — this ships into every instance and gets run from anywhere.
#
# EVERYTHING FROM A SNAPSHOT IS UNTRUSTED TEXT, AND THE SINK HERE IS A TERMINAL.
# Titles are human prose, quoting tool output and PR metadata. The HTML board escapes
# for markup; a terminal has its own metacharacters, and they are worse:
#   · a title containing ESC (`\033[2J`) would clear the screen, move the cursor, or
#     repaint what the reader has already read;
#   · a title containing a newline or a tab would forge a row or a column, so the
#     board would report work that does not exist;
#   · a bidi override (U+202E) reorders a line the reader is trying to trust.
# So clean() drops EVERY code point in Unicode general category C (control, format,
# surrogate, private-use, unassigned) and turns the whitespace controls into a single
# space. That is one rule rather than a blocklist of known-bad sequences, which is the
# same reason the writer strips C0 instead of escaping it. Colour codes on this page
# are only ever emitted by this script, never derived from a snapshot.
#
# A DRIFTED SNAPSHOT MUST NOT BLANK THE BOARD. "Malformed" splits in two, and only one
# half is a parse error:
#   · UNPARSEABLE (bad JSON, or a top level that is not an object) — that instance is
#     dropped and named in a note, so a human sees it.
#   · WRONG TYPES in valid JSON (`"tasks": "many"`, an `"order"` of `"first"`) — the
#     file parses, so nothing above catches it, and a bare int() there raises before a
#     single line is printed, taking every healthy instance down with the drifted one.
#     Every number therefore goes through toint(). Do not reintroduce a bare int() on
#     snapshot data. Same helper, same reasoning, as build-board.sh.
# An unknown task status is counted in an OTHER column and named in a note rather than
# dropped: a drifted instance should look wrong on the board, not be invisible on it.
#
# NARROW TERMINAL: NUMBERS NEVER TRUNCATE, NAMES DO, AND BELOW THE MINIMUM THE TABLE
# BECOMES A LIST. A truncated count is a WRONG number and a wrong number is worse than
# a missing one, so the numeric columns are sized to their widest value and never
# shrink. The text columns (instance, project) shrink to a floor and clip with `…`.
# When even that does not fit, the whole table is replaced by one short block per
# project — never a wrapped table, which is the mush this is avoiding. Piped output
# is UNLIMITED width and never clipped: a board redirected to a file should be
# complete, and narrowness is a property of a terminal, not of a pipe.
#
# WHY python3, WHEN EVERY OTHER SCRIPT HERE IS bash + awk. The same two reasons
# build-board.sh gives in its own header, and they did not change with the sink:
# parsing arbitrary JSON, and escaping untrusted text for the output medium. A
# hand-rolled awk JSON reader mis-handling a quote or a backslash inside a title is
# exactly the bug this file exists to prevent. `json` and `unicodedata` are standard
# library; the shell around them does the parts shell is good at (flags, TTY and
# NO_COLOR detection, terminal width). No npm, no pip, no new runtime — and python3
# was already a hard requirement of the board, so this adds no dependency.
#
# Deterministic. No network. Verified by tests/board-renderers.test.sh.
set -euo pipefail

WIDTH=""
COLOR="auto"
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --width) shift; [[ $# -gt 0 ]] || { echo "print-board: --width needs a number" >&2; exit 2; }; WIDTH="$1" ;;
    --width=*) WIDTH="${1#--width=}" ;;
    --color) shift; [[ $# -gt 0 ]] || { echo "print-board: --color needs auto|always|never" >&2; exit 2; }; COLOR="$1" ;;
    --color=*) COLOR="${1#--color=}" ;;
    --no-color) COLOR="never" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "print-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

if [[ -n "$WIDTH" ]]; then
  case "$WIDTH" in ''|*[!0-9]*) echo "print-board: --width takes a non-negative integer (0 = unlimited)" >&2; exit 2 ;; esac
fi
case "$COLOR" in auto|always|never) ;; *) echo "print-board: --color takes auto|always|never" >&2; exit 2 ;; esac

# Self-detecting, and silent when it does not apply. Not an error: this script is
# symlinked into every instance and will be run from a product repo, a worktree, or a
# home directory by accident, and a wall of usage text there is noise.
[[ -f SCHEMA.md && -f instance.config.json ]] || exit 0

TTY=0; [[ -t 1 ]] && TTY=1

# NO_COLOR's contract is "set and non-empty means no colour", hence -z rather than a
# presence test. `--color always` deliberately wins over it: the environment states a
# preference, the flag states an intention.
USE_COLOR=0
case "$COLOR" in
  always) USE_COLOR=1 ;;
  never)  USE_COLOR=0 ;;
  auto)   [[ $TTY -eq 1 && -z "${NO_COLOR:-}" ]] && USE_COLOR=1 ;;
esac

if [[ -z "$WIDTH" ]]; then
  if [[ $TTY -eq 1 ]]; then
    WIDTH="${COLUMNS:-}"
    case "$WIDTH" in ''|*[!0-9]*|0) WIDTH="$(tput cols 2>/dev/null || true)" ;; esac
    case "$WIDTH" in ''|*[!0-9]*|0) WIDTH=80 ;; esac
  else
    WIDTH=0        # unlimited — a piped board is complete, never clipped
  fi
fi

BOARD_WIDTH="$WIDTH" BOARD_COLOR="$USE_COLOR" python3 - "${DIRS[@]+"${DIRS[@]}"}" <<'PY'
import json, os, re, sys, textwrap, unicodedata
from pathlib import Path

WIDTH = int(os.environ.get("BOARD_WIDTH") or 0)      # 0 = unlimited
COLOR = os.environ.get("BOARD_COLOR") == "1"

# SCHEMA.md's Task enum, in the canonical order, plus the two derived columns. An
# unknown status lands in OTHER and is named in a note — see the header.
STATUSES = [("draft", "DRAFT"), ("ready", "READY"), ("in-progress", "PROG"),
            ("in-review", "REVIEW"), ("blocked", "BLOCK"), ("done", "DONE"),
            ("cancelled", "CANC")]
VERBS = ("approve", "answer", "merge", "unblock", "close")

DIM, BOLD, RED, YELLOW, OFF = "\033[2m", "\033[1m", "\033[31m", "\033[33m", "\033[0m"


def paint(s, code):
    return (code + s + OFF) if COLOR else s


def clean(v):
    """The single sanitising point for the TERMINAL sink; see the header.

    Every code point in Unicode general category C is dropped — control (ESC
    included, so `\033[2J` arrives as the inert text `[2J`), format (the bidi
    overrides), surrogate, private-use and unassigned. The whitespace controls become
    one space, so a title can neither forge a row (newline) nor a column (tab). Runs
    of spaces collapse, because a title padded with them would otherwise push the
    columns apart.
    """
    s = "" if v is None else str(v)
    out = []
    for ch in s:
        cat = unicodedata.category(ch)
        if cat[0] == "C":
            out.append(" " if ch in "\t\n\r\v\f" else "")
        elif cat in ("Zs", "Zl", "Zp"):
            out.append(" ")
        else:
            out.append(ch)
    # No `\s`: after the loop the only whitespace left is a plain space, and a POSIX
    # bracket form keeps this readable for whoever ports it. (An ERE `\s` here would
    # be a portability trap for the same reason the writer avoids `\b`.)
    return re.sub(r" {2,}", " ", "".join(out)).strip()


def dw(s):
    """Display width in terminal cells.

    East-Asian Wide and Fullwidth count 2. Combining marks are counted as 1 rather
    than 0, so the estimate errs toward clipping a character EARLY — which cannot
    overflow a row, only under-fill one. That is the safe direction for a layout whose
    whole job is not wrapping into mush.
    """
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def clip(s, w):
    if w <= 0 or dw(s) <= w:
        return s
    out, used = [], 0
    for ch in s:
        c = 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        if used + c > w - 1:
            break
        out.append(ch)
        used += c
    return "".join(out) + "…"


def pad(s, w, right=False):
    fill = " " * max(0, w - dw(s))
    return (fill + s) if right else (s + fill)


def tolist(v):
    return v if isinstance(v, list) else []


def todict(v):
    return v if isinstance(v, dict) else {}


def toint(v, default=0):
    """Every number in a snapshot is untrusted input — a syntactically valid file can
    still carry `"tasks": "many"`, and a bare int() there raises before a single line
    is printed, so ONE drifted instance would blank the board for every other one.
    Coerce, never trust. Same helper and same reasoning as build-board.sh."""
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def resolve_dirs(argv):
    """Named dirs, else `boardInstances`, else just this instance — never a glob.

    Copied in shape from build-board.sh's resolve_dirs, deliberately and for the same
    reason write-snapshot.sh copies validate-bundle.sh's list reader: the two
    renderers must agree about which instances are on the board, and that rule is
    stated in one place in the docs. If you change one, change both. `--list-instances`
    on build-board.sh prints what this resolves to.
    """
    if argv:
        return [Path(a).expanduser() for a in argv], None
    for name in ("instance.config.local.json", "instance.config.json"):
        cfg = Path(name)
        if not cfg.is_file():
            continue
        try:
            parsed = json.loads(cfg.read_text(encoding="utf-8"))
            # A config whose top level is a list/string/number parses fine and has no
            # .get — an AttributeError here would end the run in a traceback instead
            # of the documented fallback, so shape is checked, not assumed.
            listed = (parsed.get("boardInstances") or []) if isinstance(parsed, dict) else []
        except (ValueError, OSError, UnicodeDecodeError):
            listed = []
            print(f"print-board: {name} is unreadable; ignoring it.", file=sys.stderr)
        if isinstance(listed, list) and listed:
            return [Path(str(p)).expanduser() for p in listed], "boardInstances"
    return [Path(".")], "this instance"


dirs, source = resolve_dirs(sys.argv[1:])

instances, broken = [], []
for d in dirs:
    snap = d / "SNAPSHOT.json"
    if not d.is_dir():
        print(f"print-board: skipped {d} — no such directory.", file=sys.stderr)
        continue
    if not snap.is_file():
        # The off switch. Absent from the board entirely, by design.
        print(f"print-board: skipped {d} — no SNAPSHOT.json (off the board).", file=sys.stderr)
        continue
    try:
        data = json.loads(snap.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError, UnicodeDecodeError) as exc:
        # The directory NAME, never the path: this output gets pasted into chat and
        # tickets, and an absolute path carries the operator's home directory for no
        # reader benefit. The stderr line keeps the full path, for the one person who
        # can act on it.
        broken.append((clean(d.name or str(d)), clean(f"{type(exc).__name__}: {exc}")))
        print(f"print-board: {d}/SNAPSHOT.json is malformed — printing a note.", file=sys.stderr)
        continue
    # str(), not just truthiness: a non-string group (say 5) survives a `not` test and
    # then breaks the first thing that compares or pads it.
    data["group"] = clean(str(data.get("group") or "") or d.name.removeprefix("_ai-bridge-") or str(d))
    instances.append(data)

# ---------------------------------------------------------------- rows
rows, unknown = [], set()
n_projects = n_tasks = n_awaiting = 0
for inst in instances:
    projects = [todict(p) for p in tolist(inst.get("projects"))]
    n_projects += len(projects)
    if not projects:
        rows.append({"inst": inst["group"], "proj": "(no projects yet)",
                     "phases": "—", "vals": {}})
        continue
    for proj in projects:
        vals = {k: 0 for k, _ in STATUSES}
        vals["other"] = 0
        awaiting = 1 if proj.get("awaiting_close") else 0
        for task in (todict(t) for t in tolist(proj.get("tasks"))):
            st = clean(task.get("status"))
            if st in vals and st != "other":
                vals[st] += 1
            else:
                vals["other"] += 1
                unknown.add(st or "(empty)")
            if task.get("awaiting") in VERBS:
                awaiting += 1
            n_tasks += 1
        prog = todict(proj.get("phase_progress"))
        ptot, pdone = toint(prog.get("total")), toint(prog.get("done"))
        vals["await"] = awaiting
        n_awaiting += awaiting
        rows.append({
            "inst": inst["group"],
            "proj": clean(proj.get("title") or proj.get("slug") or "(untitled)"),
            "phases": f"{pdone}/{ptot}" if ptot else "—",
            "vals": vals,
        })

# ---------------------------------------------------------------- layout
NUMCOLS = list(STATUSES)
if any(r["vals"].get("other") for r in rows):
    NUMCOLS.append(("other", "OTHER"))
NUMCOLS.append(("await", "AWAIT"))
TOTALS = {k: sum(toint(r["vals"].get(k)) for r in rows) for k, _ in NUMCOLS}

# Two separators: the text columns get two spaces (names need the air), the numeric
# columns one (right-aligned digits do not, and seven single spaces are seven columns
# of project title bought back on an 80-column terminal).
SEP_T, SEP_N = "  ", " "

lines = []
dropped = []


def emit(s=""):
    lines.append(s)


def wrap(s, indent="", hang=""):
    """Wrap to the layout width, with an optional hanging indent for the runover.

    break_on_hyphens=False: every status in the enum is hyphenated ("in-review"), and
    textwrap's default splits on the hyphen, so a wrapped block would read "in-" /
    "review" — a name a reader cannot search for and a test cannot assert.
    """
    w = WIDTH if WIDTH else 100
    for i, ln in enumerate(textwrap.wrap(s, width=max(20, w - len(indent) - len(hang)),
                                         break_on_hyphens=False) or [""]):
        emit(indent + (hang if i else "") + ln)


if rows:
    numw = {k: max([len(h), len(str(TOTALS[k]))] + [len(str(toint(r["vals"].get(k)))) for r in rows])
            for k, h in NUMCOLS}
    inst_nat = max([dw("INSTANCE")] + [dw(r["inst"]) for r in rows])
    proj_nat = max([dw("PROJECT")] + [dw(r["proj"]) for r in rows])
    ph_w = max([dw("PHASES")] + [dw(r["phases"]) for r in rows])

    def table_width(iw, pw, cols):
        # Three text-width separators (instance|project, project|phases, phases|first
        # number), then one between each pair of numbers.
        return (iw + pw + ph_w + sum(numw[k] for k, _ in cols)
                + len(SEP_T) * 3 + len(SEP_N) * max(0, len(cols) - 1))

    # A floor, not a hard number: a board whose names are already narrower than the
    # floor cannot shrink to it, and must not be forced into the vertical fallback.
    inst_min, proj_min = min(inst_nat, 8), min(proj_nat, 12)

    cols = list(NUMCOLS)
    iw, pw = inst_nat, proj_nat

    if WIDTH:
        # STAGE 1 — drop status columns that are zero in EVERY row. A column of zeros
        # is not information and dropping one hides no work, which is exactly what
        # clipping a count would do instead. AWAIT is never dropped: it is the column
        # a human came for. Whatever went is named below the table, so nobody reads a
        # short table as "this board has no in-review column".
        for cand in [c for c in cols if c[0] != "await" and TOTALS[c[0]] == 0]:
            if table_width(iw, pw, cols) <= WIDTH:
                break
            cols.remove(cand)
            dropped.append(cand[1].lower())
        # STAGE 2 — shrink the text columns to their floor, project first (it is the
        # widest and the most tolerant of a `…`), then instance.
        over = table_width(iw, pw, cols) - WIDTH
        if over > 0:
            take = min(over, pw - proj_min); pw -= take; over -= take
        if over > 0:
            take = min(over, iw - inst_min); iw -= take; over -= take
        # STAGE 3 — still over: no table fits, so print blocks instead of wrapping a
        # table into mush.
        vertical = over > 0
    else:
        vertical = False
else:
    vertical = False

# ---------------------------------------------------------------- output
title = (f"Bridge Board · {len(instances)} instance(s) · {n_projects} project(s) · "
         f"{n_tasks} task(s) · {n_awaiting} awaiting you")
emit(paint(clip(title, WIDTH), BOLD))
emit()

if not rows:
    if broken:
        emit("No readable instance on the board.")
    else:
        wrap("No instance on the board. An instance joins once it has a SNAPSHOT.json — "
             "`touch SNAPSHOT.json` in it, then run scripts/write-snapshot.sh.")
elif vertical:
    # The narrow fallback: one block per project, never a wrapped table. Only the
    # non-zero statuses are listed — on a narrow screen the zeros are the noise.
    for r in rows:
        emit(paint(clip(f"{r['inst']} › {r['proj']}", WIDTH), BOLD))
        emit(f"  phases    {r['phases']}")
        # The full enum name here, not the column abbreviation: there is room, and a
        # narrow screen is the worst place to make a reader decode "REVW".
        parts = [f"{k} {toint(r['vals'].get(k))}" for k, _ in NUMCOLS
                 if k != "await" and toint(r["vals"].get(k))]
        wrap("tasks     " + (" · ".join(parts) if parts else "none"), "  ")
        aw = toint(r["vals"].get("await"))
        emit("  awaiting  " + (paint(str(aw), BOLD + RED) if aw else "0"))
        emit()
else:
    def line(text_cells, num_cells):
        return SEP_T.join(text_cells) + SEP_T + SEP_N.join(num_cells)

    emit(paint(line([pad("INSTANCE", iw), pad("PROJECT", pw), pad("PHASES", ph_w)],
                    [pad(h, numw[k], right=True) for k, h in cols]), DIM))
    for r in rows:
        nums = []
        for k, _ in cols:
            v = toint(r["vals"].get(k))
            cell = pad(str(v), numw[k], right=True)
            if k == "await" and v:
                cell = paint(cell, BOLD + RED)
            nums.append(cell)
        emit(line([pad(clip(r["inst"], iw), iw), pad(clip(r["proj"], pw), pw),
                   pad(r["phases"], ph_w)], nums))
    if len(rows) > 1:
        emit(paint(line([pad("", iw), pad("", pw), pad("", ph_w)],
                        ["-" * numw[k] for k, _ in cols]), DIM))
        emit(paint(line([pad("", iw), pad(clip("TOTAL", pw), pw), pad("", ph_w)],
                        [pad(str(TOTALS[k]), numw[k], right=True) for k, _ in cols]), DIM))
    if dropped:
        wrap(paint("(columns with no tasks in any row, omitted to fit the width: "
                   + ", ".join(dropped) + ")", DIM))

# ---- notes: a broken instance is VISIBLE here, never a silent absence
if (broken or unknown) and lines and lines[-1] != "":
    emit()
for name, msg in broken:
    wrap(paint(f"! {name}: unreadable SNAPSHOT.json — that instance is not on the board. "
               f"Re-run scripts/write-snapshot.sh there. ({msg})", YELLOW), hang="  ")
if unknown:
    wrap(paint("! task status(es) outside the schema enum, counted under OTHER: "
               + ", ".join(sorted(unknown))
               + " — a drifted instance; run scripts/validate-bundle.sh there.", YELLOW),
         hang="  ")

if lines and lines[-1] != "":
    emit()
wrap(paint("Read from each instance's SNAPSHOT.json — derived, and as sensitive as the task "
           "documents it comes from. Instances listed from: "
           + (source or "command line") + ".", DIM))

sys.stdout.write("\n".join(lines) + "\n")
PY
