#!/usr/bin/env bash
#
# build-board.sh — render every instance's SNAPSHOT.json as ONE self-contained HTML
# page, in either of two layouts.
#
#   Usage:
#     scripts/build-board.sh [--layout columns|table] [--out FILE] [--standalone] [INSTANCE_DIR ...]
#     scripts/build-board.sh --list-instances [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render. With none given, the list comes
#                       from `boardInstances` in ./instance.config.local.json, else
#                       ./instance.config.json; if that key
#                       is absent or empty, just this instance.
#     --layout NAME     which markup to emit, `columns` (the default) or `table`:
#                       · columns — instance → project → phase progress → a column per
#                         task status. Every instance on one page, behind CSS-only tabs.
#                       · table — projects collapsed to one summary line, expandable to
#                         their task table, with a decision rail on top. The owner picked
#                         this one for PUBLISHING as "more readable and easier to act
#                         upon": a page a teammate opens on a phone, not a wall of
#                         columns.
#     --out FILE        where to write (default: ./board.html, for both layouts — it is
#                       the path an instance's .gitignore already covers)
#     --standalone      wrap the output in <!doctype html>/<head> for opening in a
#                       browser directly. OMIT for publishing (see OUTPUT SHAPE).
#                       ORTHOGONAL to --layout, and deliberately so: layout is markup,
#                       standalone is wrapping. Either layout can be either.
#     --list-instances  print the resolved instance directories, one per line, and
#                       exit without writing anything. This exists so watch-board.sh
#                       can learn WHICH directories to watch without carrying a third
#                       copy of the discovery rule below — one script owns it.
#
# WHY ONE SCRIPT WITH TWO LAYOUTS, AND NOT TWO SCRIPTS. It was two: this file and a
# `build-artifact-board.sh`, 1,139 lines between them, reading the same snapshot
# contract, sharing the same instance discovery, and differing only in markup. The
# duplication was created knowingly, because both layouts were wanted — but two files
# also meant two copies of the parts a board must not get wrong, and the second copy was
# the weaker one: it wrote a PR URL into an `href` without checking its scheme and read
# every count with a bare `.get()`, so both hardening rules below existed in one file and
# not the other. One script, one hardened path, `--layout` for the markup.
#
# DISCOVERY IS EXPLICIT, NEVER A GLOB. This file is symlinked into every instance,
# so it may not know where anybody's workspace lives — no `~/workspace/*`, no
# guessing at sibling directories. Either you name the instances or the instance's
# own config does, and an unnamed instance is simply not on the board.
#
# ABSENCE IS THE OFF SWITCH, ON BOTH SIDES. An instance with no SNAPSHOT.json does
# not appear — no placeholder, no warning card, nothing (the run says so on stderr,
# where it costs a human nothing). See write-snapshot.sh for why that is permanent.
#
# EVERYTHING FROM A SNAPSHOT IS UNTRUSTED TEXT. Titles, descriptions and URLs come
# from task documents: human-written, quoting tool output and PR metadata, and none
# of it authored here. This is the same boundary show-awaiting.sh keeps when it
# fences items before they enter session context (see its closing comment) — the
# difference is only the sink. Here the sink is an HTML page that gets published, so:
#   · every string is HTML-escaped, attribute values included, at the single point
#     where it is written into the page;
#   · a URL is rendered as a link ONLY if its scheme is http/https — a `javascript:`
#     or `data:` PR URL renders as inert text. The writer already restricts what it
#     collects; the board does not trust it to have done so;
#   · nothing from a snapshot ever reaches a <script>, a style, or an event handler;
#   · no filesystem path reaches the page — an instance is identified by its directory
#     NAME, because a published board should not carry anybody's home directory.
# A malformed snapshot is a visible card, not a crash: a broken instance must not be
# able to blank the board for the others. That promise has TWO halves, because a
# snapshot can be broken in two different ways, and only one of them is a parse error:
#   · UNPARSEABLE (bad JSON, or a top level that is not an object) — the instance is
#     dropped and rendered as a named "Unreadable snapshot" note, so a human sees it.
#   · WRONG TYPES in valid JSON (`"tasks": "many"`, a non-string `group`) — the file
#     parses, so nothing above catches it; the wrong type surfaces later at an int()
#     or a sort comparison, and an uncaught ValueError/TypeError there means NO output
#     file is written at all. Every number therefore goes through toint() and `group`
#     is forced to str(), so the drifted field degrades to 0 while the instance and
#     every other instance still render. Coercion, not a note, is deliberate here: a
#     single junk count is not worth hiding a whole instance's real work behind a
#     warning card. Do not reintroduce a bare int() on snapshot data.
#
# WHY python3 AND NOT awk. Every other script here is bash + awk on purpose, so it
# ships into an instance unchanged. This one needs two things awk does badly and a
# board cannot be wrong about: parsing arbitrary JSON, and HTML-escaping. A
# hand-rolled JSON reader mis-handling a quote inside a title is exactly the bug that
# turns an untrusted title into markup on a published page. `json` and
# `html.escape(..., quote=True)` are the right primitives, they are in the standard
# library, and this is a human-run reporting step — not tick machinery a /pm-loop
# depends on. No npm, no pip, no new runtime.
#
# OUTPUT SHAPE. The default output is an **Artifact page body**: a <title>, an inline
# <style>, then content — no <!doctype>, <html>, <head> or <body> tags, because the
# publish step wraps the file in exactly those. Opening that file in a browser
# directly works but lands in quirks mode with no charset declared; use
# `--standalone` for a local look, and the plain file for publishing.
#
# WHAT IS TRUE OF THE `table` LAYOUT AND NOT THE `columns` ONE. Read this before
# assuming one set of promises covers both.
#   · It uses <details>, never script, for collapsing. The first version of it rendered
#     from JavaScript and toggled with a click handler; two bugs came out of that and
#     NEITHER WAS DIAGNOSABLE IN PLACE, because the artifact host serves the page in an
#     iframe that exposes neither its console nor its accessibility tree, so a blank
#     page had no error to read. <details> needs no script, works with scripting off, is
#     keyboard-accessible for free, and its open/closed state is per-viewer.
#   · It DOES carry one <script> and one external <link>: a clipboard helper (a browser
#     cannot open a local file, so a task copies a SHORT REFERENCE — `<project>/tasks/<id>`
#     — instead of a link, and every button says what it copied so a failed copy is
#     visible rather than silent) and a webfont stylesheet. The `columns` layout has
#     neither, and tests/snapshot.test.sh pins that for it — "zero external requests, no
#     <script> at all" is a property of the DEFAULT layout, not of this file.
#   · Its decision rail surfaces one thing the awaiting queue does not: an open question
#     on a task that is no longer a draft. write-snapshot.sh only emits an `awaiting`
#     verb for a question while the task IS a draft, so such a question is invisible in
#     the queue; the rail adds it at the presentation layer, without touching the
#     AWAITING.md contract that awaiting-queue.test.sh pins. That is why the two layouts
#     derive their queues separately here rather than sharing one list.
#   · With no readable snapshot it writes NOTHING and exits 0, where `columns` writes a
#     page carrying an empty-state note. Publishing an empty board is not useful; being
#     told locally how to get on the board is.
#
# Deterministic. No network at build time. Verified by tests/snapshot.test.sh (the
# writer and the columns layout), tests/board-renderers.test.sh (the other renderers,
# and the table layout) and tests/machinery-ceiling.test.sh (this file's size).
set -euo pipefail

OUT="board.html"
STANDALONE=0
LIST_ONLY=0
LAYOUT="columns"
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "build-board: --out needs a path" >&2; exit 2; }; OUT="$1" ;;
    --out=*) OUT="${1#--out=}" ;;
    --layout) shift; [[ $# -gt 0 ]] || { echo "build-board: --layout needs columns|table" >&2; exit 2; }; LAYOUT="$1" ;;
    --layout=*) LAYOUT="${1#--layout=}" ;;
    --standalone) STANDALONE=1 ;;
    --list-instances) LIST_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "build-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done
case "$LAYOUT" in
  columns|table) ;;
  *) echo "build-board: unknown layout '$LAYOUT' (columns|table)" >&2; exit 2 ;;
esac

command -v python3 >/dev/null 2>&1 || {
  echo "build-board: needs python3 (standard library only). See this script's header for why." >&2
  exit 2
}

BOARD_OUT="$OUT" BOARD_STANDALONE="$STANDALONE" BOARD_LIST_ONLY="$LIST_ONLY" \
BOARD_LAYOUT="$LAYOUT" \
  python3 - "${DIRS[@]+"${DIRS[@]}"}" <<'PY'
import html, json, os, re, sys
from pathlib import Path

OUT = Path(os.environ["BOARD_OUT"])
STANDALONE = os.environ.get("BOARD_STANDALONE") == "1"
LAYOUT = os.environ.get("BOARD_LAYOUT") or "columns"

# Canonical column order — SCHEMA.md's Task enum. An unknown status still gets a
# column at the end rather than vanishing: a snapshot from a drifted instance should
# look wrong on the board, not be silently dropped from it.
COLUMNS = ["draft", "ready", "in-progress", "in-review", "blocked", "done", "cancelled"]
VERBS = {"approve": "✅", "answer": "❓", "merge": "🔀", "unblock": "⛔", "close": "🏁"}

def e(v):
    """The single escape point. Everything from a snapshot goes through here."""
    return html.escape("" if v is None else str(v), quote=True)

def href(url):
    """A link only for http/https. Anything else is inert text (see header)."""
    u = "" if url is None else str(url)
    return u if u.lower().startswith(("http://", "https://")) else ""

def dirname(d):
    """The directory's own name — never a path.

    `.resolve()` first, because the default discovery target is Path("."), whose
    `.name` is EMPTY: a snapshot carrying no `group` (exactly what install.sh seeds
    on a first stamp) then fell through to str(d) and labelled the instance ".".
    Resolving yields the real basename, and taking only the basename keeps the
    published-page rule intact — a name leaves, a path never does.
    """
    try:
        return d.resolve().name
    except OSError:
        return d.name


def resolve_dirs(argv):
    if argv:
        return [Path(a).expanduser() for a in argv], None
    # `boardInstances` is an OVERRIDABLE key: the gitignored instance.config.local.json
    # wins over the tracked instance.config.json. It is a list of filesystem PATHS
    # (expanduser below), so it is machine-shaped by the same test as reposRoot and
    # worktreeRoot — the sibling instances a second clone can see are its own business.
    # Absent (or empty) local file ⇒ the tracked file answers, exactly as before.
    # Full overridable set: SCHEMA.md → "Per-machine config overrides".
    for name in ("instance.config.local.json", "instance.config.json"):
        cfg = Path(name)
        if not cfg.is_file():
            continue
        try:
            parsed = json.loads(cfg.read_text(encoding="utf-8"))
            # A config whose top level is a list/string/number parses fine but has no
            # .get — an AttributeError here would end the run in a traceback instead of
            # the documented fallback, so shape is checked, not assumed.
            listed = (parsed.get("boardInstances") or []) if isinstance(parsed, dict) else []
        except (ValueError, OSError, UnicodeDecodeError):
            listed = []
            # Say only what is true: an unreadable LOCAL file still lets the tracked
            # one answer on the next pass, so this must not claim the final fallback.
            print(f"build-board: {name} is unreadable; ignoring it.", file=sys.stderr)
        if isinstance(listed, list) and listed:
            return [Path(str(p)).expanduser() for p in listed], "boardInstances"
    return [Path(".")], "this instance"

dirs, source = resolve_dirs(sys.argv[1:])

# --list-instances: answer the discovery question and stop, writing nothing. It is
# deliberately the SAME resolve_dirs call the render path uses — a second
# implementation of the rule is a second thing to drift. Paths only, one per line, so
# a caller can read them into a shell array.
if os.environ.get("BOARD_LIST_ONLY") == "1":
    for d in dirs:
        # One path per LINE, so a path containing a newline would forge an entry in
        # the caller's array — the same class as push-state.sh encoding every
        # file-derived value to one line. `boardInstances` is human-written JSON, where
        # a "\n" is legal, so this is a refusal rather than an escape: an unusable name
        # is named on stderr and dropped, never silently split in two.
        if "\n" in str(d) or "\r" in str(d):
            print(f"build-board: skipping an instance path containing a newline: {d!r}",
                  file=sys.stderr)
            continue
        print(d)
    sys.exit(0)

instances, broken = [], []
for d in dirs:
    snap = d / "SNAPSHOT.json"
    if not d.is_dir():
        print(f"build-board: skipped {d} — no such directory.", file=sys.stderr)
        continue
    if not snap.is_file():
        # The off switch. Absent from the board entirely, by design.
        print(f"build-board: skipped {d} — no SNAPSHOT.json (off the board).", file=sys.stderr)
        continue
    try:
        data = json.loads(snap.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError, UnicodeDecodeError) as exc:
        # The DIRECTORY NAME, never the path: this page can be published, and an
        # absolute path leaks the operator's home directory and username for no
        # reader benefit. The stderr line above still carries the full path, where
        # the person who can fix it is the only one reading.
        broken.append((dirname(d) or str(d), type(exc).__name__ + ": " + str(exc)))
        print(f"build-board: {d}/SNAPSHOT.json is malformed — rendering a note.", file=sys.stderr)
        continue
    data["_dir"] = dirname(d) or str(d)   # name, not path — see the note above
    # str(), not just truthiness: a non-string group (say 5) survives a `not` test and
    # then makes the awaiting sort compare int with str, which raises TypeError.
    data["group"] = str(data.get("group") or "") or dirname(d).removeprefix("_ai-bridge-") or str(d)
    instances.append(data)

def tolist(v):
    return v if isinstance(v, list) else []

def todict(v):
    return v if isinstance(v, dict) else {}

def toint(v, default=0):
    """Every number in a snapshot is untrusted input. A syntactically valid file can
    still carry `"tasks": "many"`, and a bare int() there raises ValueError before a
    single byte is written — so ONE drifted instance would blank the board for every
    other instance, breaking the header's promise that a malformed snapshot is a
    visible card rather than a crash. Coerce, never trust."""
    try:
        return int(v)
    except (TypeError, ValueError):
        return default

# ---------------------------------------------------------------- awaiting queue
# The AWAITING.md contract, read off the snapshot: one entry per thing a human decision
# unblocks. Shared by the columns layout and by the summary line both layouts print.
awaiting = []
for inst in instances:
    for proj in tolist(inst.get("projects")):
        proj = todict(proj)
        if proj.get("awaiting_close"):
            awaiting.append({
                "verb": "close", "group": inst["group"], "project": proj.get("title") or proj.get("slug"),
                "what": "all tasks terminal", "detail": "/close-project " + str(proj.get("slug") or ""), "prs": [],
            })
        for task in tolist(proj.get("tasks")):
            task = todict(task)
            verb = task.get("awaiting")
            if verb in VERBS:
                awaiting.append({
                    "verb": verb, "group": inst["group"], "project": proj.get("title") or proj.get("slug"),
                    "what": task.get("title") or task.get("id"),
                    "detail": (f"{task.get('open_questions')} open question(s)" if verb == "answer" else ""),
                    "prs": tolist(task.get("prs")),
                })
ORDER = list(VERBS)
awaiting.sort(key=lambda a: (ORDER.index(a["verb"]), a["group"], str(a["project"])))

# ---------------------------------------------------------------- columns layout
CSS = """
/* Full light palette on BARE :root, so no colour is ever defined only inside a
   media or [data-theme] block. Dark redefines these same tokens twice: once for
   the system preference (guarded so an explicit light choice wins) and once for an
   explicit dark choice. */
:root{
  --bg:#f6f7f9; --surface:#ffffff; --surface-2:#eef0f4; --border:#d7dbe2;
  --text:#12161c; --text-dim:#5b6472; --accent:#2f5fd0; --accent-soft:#e6edfb;
  --warn-bg:#fdf1e3; --warn-border:#e0a94a; --shadow:0 1px 2px rgba(16,22,32,.07);
  --draft:#8b7bd8; --ready:#2f8f5b; --in-progress:#c98a17; --in-review:#2f5fd0;
  --blocked:#c5443c; --done:#5b6472; --cancelled:#8a9099; --other:#8a9099;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0f1216; --surface:#171b21; --surface-2:#1e242c; --border:#2c343e;
    --text:#e7ebf0; --text-dim:#98a2b0; --accent:#7aa2f7; --accent-soft:#1d2637;
    --warn-bg:#2a2115; --warn-border:#6b5220; --shadow:0 1px 2px rgba(0,0,0,.4);
    --draft:#a996f2; --ready:#5cc98c; --in-progress:#e3b04b; --in-review:#7aa2f7;
    --blocked:#f0776e; --done:#98a2b0; --cancelled:#78818d; --other:#78818d;
  }
}
:root[data-theme="dark"]{
  --bg:#0f1216; --surface:#171b21; --surface-2:#1e242c; --border:#2c343e;
  --text:#e7ebf0; --text-dim:#98a2b0; --accent:#7aa2f7; --accent-soft:#1d2637;
  --warn-bg:#2a2115; --warn-border:#6b5220; --shadow:0 1px 2px rgba(0,0,0,.4);
  --draft:#a996f2; --ready:#5cc98c; --in-progress:#e3b04b; --in-review:#7aa2f7;
  --blocked:#f0776e; --done:#98a2b0; --cancelled:#78818d; --other:#78818d;
}
*,*::before,*::after{box-sizing:border-box}
body{
  margin:0; padding:1rem .85rem 3rem;
  background:var(--bg); color:var(--text);
  font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  -webkit-text-size-adjust:100%; overflow-x:hidden;
}
img,svg{max-width:100%}
.wrap{max-width:78rem; margin:0 auto}
h1{font-size:1.35rem; margin:0 0 .2rem; letter-spacing:-.01em}
h2{font-size:1.05rem; margin:1.6rem 0 .6rem}
h3{font-size:.98rem; margin:0}
.sub{color:var(--text-dim); font-size:.82rem; margin:0 0 1.2rem}
a{color:var(--accent)}
.card{background:var(--surface); border:1px solid var(--border); border-radius:.7rem; box-shadow:var(--shadow)}
.pill{display:inline-block; padding:.08rem .45rem; border-radius:1rem; font-size:.7rem;
  font-weight:600; text-transform:uppercase; letter-spacing:.03em;
  background:var(--surface-2); color:var(--text-dim); white-space:nowrap}
.pill[data-s]{color:var(--surface)}
.pill[data-s="draft"]{background:var(--draft)} .pill[data-s="ready"]{background:var(--ready)}
.pill[data-s="in-progress"]{background:var(--in-progress)} .pill[data-s="in-review"]{background:var(--in-review)}
.pill[data-s="blocked"]{background:var(--blocked)} .pill[data-s="done"]{background:var(--done)}
.pill[data-s="cancelled"]{background:var(--cancelled)} .pill[data-s="other"]{background:var(--other)}

/* --- awaiting you: the one thing on this page that needs a decision --- */
.awaiting{border-left:.28rem solid var(--blocked); padding:.85rem .9rem; margin:0 0 1.4rem}
.awaiting h2{margin:0 0 .55rem; font-size:1rem}
.awaiting ul{list-style:none; margin:0; padding:0; display:grid; gap:.5rem}
.awaiting li{display:flex; flex-wrap:wrap; gap:.4rem .55rem; align-items:baseline;
  padding:.45rem .55rem; background:var(--surface-2); border-radius:.45rem; font-size:.9rem}
.awaiting .verb{font-weight:700; white-space:nowrap}
.awaiting .where{color:var(--text-dim); font-size:.78rem; width:100%}
.none{color:var(--text-dim); font-size:.9rem; margin:0}

/* --- instance tabs: CSS-only, so no script and full keyboard support --- */
.tabs>input{position:absolute; opacity:0; pointer-events:none; width:0; height:0}
.tablist{display:flex; flex-wrap:wrap; gap:.4rem; margin:0 0 1rem}
.tablist label{cursor:pointer; padding:.35rem .7rem; border:1px solid var(--border);
  border-radius:.5rem; background:var(--surface); font-size:.85rem; font-weight:600}
.tabs>input:focus-visible+.tablist label[data-first],
.tablist label:hover{border-color:var(--accent)}
.panel{display:none}

/* --- a project --- */
.project{padding:.85rem .9rem; margin:0 0 1rem}
.phead{display:flex; flex-wrap:wrap; gap:.4rem .6rem; align-items:baseline}
.pdesc{color:var(--text-dim); font-size:.85rem; margin:.35rem 0 0}
.progress{margin:.6rem 0 .2rem; font-size:.75rem; color:var(--text-dim)}
.bar{height:.4rem; border-radius:1rem; background:var(--surface-2); overflow:hidden; margin-top:.25rem}
.bar>span{display:block; height:100%; background:var(--accent)}
.phaselist{margin:.45rem 0 0; padding:0; list-style:none; display:flex; flex-wrap:wrap; gap:.3rem}
.phaselist li{font-size:.72rem; color:var(--text-dim); background:var(--surface-2);
  border-radius:.35rem; padding:.1rem .4rem}

/* --- the columns. Wide content scrolls INSIDE this strip; the body never does. --- */
.cols{display:flex; gap:.6rem; overflow-x:auto; padding:.7rem .1rem .3rem;
  scroll-snap-type:x proximity; -webkit-overflow-scrolling:touch}
.col{flex:0 0 15rem; min-width:15rem; scroll-snap-align:start;
  background:var(--surface-2); border-radius:.55rem; padding:.5rem}
@media (min-width:52rem){ .col{flex:1 1 0; min-width:11rem} }
.colhead{display:flex; justify-content:space-between; align-items:baseline;
  font-size:.74rem; font-weight:700; text-transform:uppercase; letter-spacing:.04em;
  color:var(--text-dim); margin:0 0 .45rem}
.task{background:var(--surface); border:1px solid var(--border); border-radius:.45rem;
  padding:.45rem .5rem; margin:0 0 .4rem; font-size:.85rem}
.task .t{overflow-wrap:anywhere}
.task .meta{display:flex; flex-wrap:wrap; gap:.3rem; align-items:center; margin-top:.35rem}
.task .flight{color:var(--in-progress); font-size:.7rem; font-weight:700}
.task .prs{display:flex; flex-wrap:wrap; gap:.25rem; margin-top:.3rem}
.task .prs a{font-size:.72rem; background:var(--accent-soft); color:var(--accent);
  border-radius:.3rem; padding:.05rem .35rem; text-decoration:none; white-space:nowrap}
.task .inert{font-size:.72rem; color:var(--text-dim); overflow-wrap:anywhere}
.empty{color:var(--text-dim); font-size:.78rem; padding:.2rem .1rem}

.note{background:var(--warn-bg); border:1px solid var(--warn-border); border-radius:.55rem;
  padding:.6rem .7rem; margin:0 0 .8rem; font-size:.85rem}
.note code{overflow-wrap:anywhere}
footer{color:var(--text-dim); font-size:.75rem; margin-top:2rem; border-top:1px solid var(--border); padding-top:.7rem}
table{border-collapse:collapse}
.scroll{overflow-x:auto}
"""


def render_columns():
    """Two lists, because --standalone has to put each in the right place: HEAD holds
    <title>/<meta>/<style>, BODY holds the content. Emitting the content inside <head>
    (with an empty <body> after it) is valid-looking and wrong — the parser recovers by
    implicitly closing <head>, so it renders while the file lies about its structure."""
    head, parts = [], []
    wh = head.append
    w = parts.append

    wh("<title>Bridge Board</title>")
    wh('<meta name="viewport" content="width=device-width, initial-scale=1">')
    wh("<style>" + CSS)
    # The tab rules are generated: one pair per instance, so the CSS-only tabs need no JS.
    for i in range(len(instances)):
        wh(f'.tabs>#tab-{i}:checked ~ #panel-{i}{{display:block}}')
        wh(f'.tabs>#tab-{i}:checked ~ .tablist label[for="tab-{i}"]'
           '{background:var(--accent-soft); border-color:var(--accent); color:var(--accent)}')
    wh("</style>")

    w('<div class="wrap">')
    w("<h1>Bridge Board</h1>")
    total_tasks = sum(toint(todict(i.get("counts")).get("tasks")) for i in instances)
    w('<p class="sub">{} instance(s) · {} project(s) · {} task(s) · {} awaiting you</p>'.format(
        len(instances),
        sum(len(tolist(i.get("projects"))) for i in instances),
        total_tasks, len(awaiting)))

    for d, msg in broken:
        w('<div class="note"><strong>Unreadable snapshot.</strong> '
          f'<code>{e(d)}/SNAPSHOT.json</code> could not be parsed, so that instance is not on '
          f'the board. Re-run <code>scripts/write-snapshot.sh</code> there. <br>{e(msg)}</div>')

    # ---- awaiting you
    w('<section class="card awaiting">')
    w(f"<h2>🔴 Awaiting you ({len(awaiting)})</h2>")
    if awaiting:
        w("<ul>")
        for a in awaiting:
            w("<li>")
            w(f'<span class="verb">{VERBS[a["verb"]]} {e(a["verb"])}</span>')
            w(f'<span>{e(a["what"])}</span>')
            for pr in tolist(a["prs"]):
                pr = todict(pr)
                u = href(pr.get("url"))
                label = f'{pr.get("repo")}#{pr.get("number")}'
                if u:
                    w(f'<a href="{e(u)}" rel="noopener noreferrer" target="_blank">{e(label)}</a>')
                else:
                    w(f'<span class="inert">{e(label)}</span>')
            tail = f' · {a["detail"]}' if a["detail"] else ""
            w(f'<span class="where">{e(a["group"])} › {e(a["project"])}{e(tail)}</span>')
            w("</li>")
        w("</ul>")
    else:
        w('<p class="none">Nothing needs a decision right now.</p>')
    w("</section>")

    # ---- instances
    if not instances:
        w('<div class="note">No instance on the board. An instance appears here once it has a '
          '<code>SNAPSHOT.json</code> — <code>touch SNAPSHOT.json</code> in it, then run '
          '<code>scripts/write-snapshot.sh</code>.</div>')
    else:
        w('<div class="tabs">')
        for i in range(len(instances)):
            checked = " checked" if i == 0 else ""
            w(f'<input type="radio" name="board-instance" id="tab-{i}"{checked}>')
        w('<nav class="tablist">')
        for i, inst in enumerate(instances):
            n = len(tolist(inst.get("projects")))
            w(f'<label for="tab-{i}"{" data-first" if i == 0 else ""}>{e(inst["group"])} '
              f'<span class="pill">{n}</span></label>')
        w("</nav>")

        for i, inst in enumerate(instances):
            w(f'<section class="panel" id="panel-{i}">')
            w(f'<p class="sub">snapshot generated {e(inst.get("generated_at") or "unknown")} · '
              f'<code>{e(inst.get("_dir"))}</code></p>')
            projects = [todict(p) for p in tolist(inst.get("projects"))]
            if not projects:
                w('<p class="none">No projects in this instance yet.</p>')
            for proj in projects:
                w('<article class="card project">')
                w('<div class="phead">')
                w(f'<h3>{e(proj.get("title") or proj.get("slug"))}</h3>')
                st = proj.get("status") or "other"
                w(f'<span class="pill" data-s="{e(st if st in COLUMNS or st in ("active","paused","done") else "other")}">{e(st)}</span>')
                w(f'<span class="pill">{e(proj.get("kind") or "build")}</span>')
                if (proj.get("autonomy") or "gated") != "gated":
                    w(f'<span class="pill" data-s="blocked">autonomy: {e(proj.get("autonomy"))}</span>')
                if proj.get("awaiting_close"):
                    w('<span class="pill" data-s="ready">🏁 close?</span>')
                w("</div>")
                if proj.get("description"):
                    w(f'<p class="pdesc">{e(proj.get("description"))}</p>')

                prog = todict(proj.get("phase_progress"))
                ptot = toint(prog.get("total"))
                pdone = toint(prog.get("done"))
                if ptot:
                    pct = max(0, min(100, round(100 * pdone / ptot)))
                    w(f'<div class="progress">Phases {pdone}/{ptot} done'
                      f'<div class="bar"><span style="width:{pct}%"></span></div></div>')
                    w('<ul class="phaselist">')
                    for ph in sorted((todict(p) for p in tolist(proj.get("phases"))),
                                     key=lambda p: (toint(p.get("order")), str(p.get("title") or ""))):
                        w(f'<li>{e(ph.get("order"))}. {e(ph.get("title"))} — {e(ph.get("status"))}</li>')
                    w("</ul>")

                tasks = [todict(t) for t in tolist(proj.get("tasks"))]
                if not tasks:
                    w('<p class="empty">No tasks yet.</p>')
                else:
                    buckets = {c: [] for c in COLUMNS}
                    for t in tasks:
                        buckets.setdefault(t.get("status") or "other", []).append(t)
                    order = COLUMNS + [k for k in buckets if k not in COLUMNS]
                    w('<div class="cols">')
                    for col in order:
                        items = buckets.get(col) or []
                        w('<div class="col">')
                        label = col if col in COLUMNS else (col or "unknown")
                        w(f'<div class="colhead"><span>{e(label)}</span><span>{len(items)}</span></div>')
                        if not items:
                            w('<div class="empty">—</div>')
                        for t in items:
                            w('<div class="task">')
                            w(f'<div class="t">{e(t.get("title") or t.get("id"))}</div>')
                            w('<div class="meta">')
                            w(f'<span class="pill">{e(t.get("id"))}</span>')
                            if t.get("assignee"):
                                w(f'<span class="pill">{e(t.get("assignee"))}</span>')
                            if t.get("in_flight"):
                                w('<span class="flight">● in flight</span>')
                            if t.get("awaiting") in VERBS:
                                w(f'<span class="pill" data-s="blocked">{VERBS[t["awaiting"]]} {e(t["awaiting"])}</span>')
                            oq = t.get("open_questions") or 0
                            if isinstance(oq, int) and oq > 0:
                                w(f'<span class="pill">{oq} question(s)</span>')
                            w("</div>")
                            prs = [todict(p) for p in tolist(t.get("prs"))]
                            if prs:
                                w('<div class="prs">')
                                for pr in prs:
                                    u = href(pr.get("url"))
                                    label = f'{pr.get("repo")}#{pr.get("number")}'
                                    if u:
                                        w(f'<a href="{e(u)}" rel="noopener noreferrer" target="_blank">{e(label)}</a>')
                                    else:
                                        w(f'<span class="inert">{e(label)} (link withheld: not http/https)</span>')
                                w("</div>")
                            w("</div>")
                        w("</div>")
                    w("</div>")
                w("</article>")
            w("</section>")
        w("</div>")

    w("<footer>Generated by <code>scripts/build-board.sh</code> from each instance's "
      "<code>SNAPSHOT.json</code>. Derived, read-only, and <strong>as sensitive as the task "
      "documents it comes from</strong> — every title here is human-written free text. "
      f"Instances listed from: {e(source or 'command line')}.</footer>")
    w("</div>")
    return head, parts


# ---------------------------------------------------------------- table layout
TONE = {"blocked": "stop", "review": "signal", "in-review": "signal",
        "done": "ok", "in-progress": "accent"}
PENDING = ("draft", "ready", "blocked")
RUNNING = ("in-progress", "in-review", "review")
WORDING = {
    "approve": ("Approve", "go", "APPROVED — go ahead."),
    "discuss": ("Let’s discuss", "", "I want to discuss this before you proceed."),
    "reject": ("Reject", "no", "REJECTED — do not proceed."),
}

TABLE_HEAD = """<title>__TITLE__</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500;600&display=swap">
<style>
/* Full light palette on BARE :root — no colour is ever defined only inside a media
   or [data-theme] block. Dark redefines the same tokens twice: once for the system
   preference (guarded so an explicit light choice wins), once for an explicit choice. */
:root{
  --ground:#f4f6f7; --surface:#fff; --sunk:#eceff1; --raise:#f8fafb;
  --ink:#15181d; --muted:#5c6470; --dim:#89919c; --line:#dde2e6;
  --accent:#0f6b66; --signal:#9c560d; --ok:#2c6647; --stop:#a03a32;
  --shadow:0 1px 2px rgba(20,26,34,.05),0 8px 24px -16px rgba(20,26,34,.22);
}
@media (prefers-color-scheme:dark){ :root:not([data-theme="light"]){
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}}
:root[data-theme="dark"]{
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}
*,*::before,*::after{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);margin:0;
  font:400 15px/1.55 "IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.board{width:min(100% - 2rem, 104rem);margin:0 auto;display:flex;flex-direction:column;
  gap:1.1rem;padding:clamp(1.4rem,3vw,2.6rem) 0 4rem}
/* Prose keeps a readable measure even when the board is wide — only the data grows. */
.sub,.where,footer p{max-width:52rem}

.mast{display:flex;flex-wrap:wrap;gap:1.3rem;justify-content:space-between;
  align-items:flex-end;padding-bottom:1rem;border-bottom:2px solid var(--ink)}
h1{font-size:clamp(1.5rem,3.6vw,1.95rem);font-weight:600;letter-spacing:-.02em;
  margin:0;text-wrap:balance}
.sub{color:var(--muted);margin:.28rem 0 0;font-size:.82rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace}
.tally{display:flex;gap:1.5rem;margin:0}
.tally div{display:flex;flex-direction:column-reverse;gap:.1rem}
.tally dt{font-size:.65rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);margin:0}
.tally dd{margin:0;font:600 1.5rem/1 "IBM Plex Mono",ui-monospace,monospace;
  color:var(--muted);font-variant-numeric:tabular-nums}
.tally .live dd,.tally .live dt{color:var(--signal)}

.rail{border-left:.22rem solid var(--signal);border-radius:0 6px 6px 0;
  background:color-mix(in srgb,var(--signal) 8%,var(--surface));padding:.9rem 1rem}
.rail h2{margin:0 0 .7rem;font-size:.68rem;text-transform:uppercase;letter-spacing:.1em;
  color:var(--signal);font-weight:600}
.rail ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.6rem}
.ask{display:flex;flex-direction:column;gap:.5rem;padding:.65rem .75rem;
  background:var(--surface);border:1px solid var(--line);border-radius:5px}
/* A snapshot that could not be parsed is a VISIBLE note here too, not just a line on
   stderr — one broken instance must not be able to disappear quietly. Named
   `.snapnote` rather than `.note`, because `.c.note` below is the advisor-concern
   pill and a bare `.note` rule would restyle it. */
.snapnote{border:1px solid var(--stop);border-left:.22rem solid var(--stop);
  border-radius:5px;padding:.7rem .85rem;font-size:.84rem;color:var(--muted);
  background:var(--surface)}
.line{display:flex;flex-wrap:wrap;gap:.3rem .55rem;align-items:baseline}
.what{font-weight:500}
.verb{font:600 .64rem/1.7 "IBM Plex Mono",ui-monospace,monospace;text-transform:uppercase;
  letter-spacing:.08em;color:var(--signal);white-space:nowrap}
.where{width:100%;font-size:.75rem;color:var(--dim)}
.acts{display:flex;flex-wrap:wrap;gap:.35rem}
/* The title line IS the toggle: click anywhere on it for the explanation. A caret
   marks it as expandable, since a heading that happens to be clickable is invisible. */
.why summary{cursor:pointer;list-style:none}
.why summary::-webkit-details-marker{display:none}
.why summary::after{content:"▸";color:var(--dim);font-size:.7rem;
  transition:transform .15s;display:inline-block;margin-left:.15rem}
.why[open] summary::after{transform:rotate(90deg)}
.why summary:hover .what{color:var(--accent)}
.why summary:hover::after{color:var(--accent)}
.why p{margin:.55rem 0 0;color:var(--muted);line-height:1.5;max-width:52rem;
  font-size:.83rem;border-left:2px solid var(--line);padding-left:.6rem}
button{font:500 .78rem/1 "IBM Plex Sans",sans-serif;cursor:pointer;border-radius:4px;
  padding:.38rem .62rem;border:1px solid var(--line);background:var(--raise);
  color:var(--ink)}
button:hover{border-color:var(--accent)}
button.go{border-color:var(--ok);color:var(--ok)}
button.no{border-color:var(--stop);color:var(--stop)}

/* Collapsed by default: no `open` attribute, and no script involved. */
.proj{background:var(--surface);border:1px solid var(--line);border-radius:6px;
  box-shadow:var(--shadow)}
.phead{display:flex;flex-wrap:wrap;gap:.5rem .9rem;align-items:center;cursor:pointer;
  padding:.8rem .95rem;list-style:none;border-radius:6px}
.phead::-webkit-details-marker{display:none}
.phead::before{content:"\\25B8";color:var(--dim);font-size:.8rem;flex-shrink:0;
  transition:transform .15s}
.proj[open] .phead::before{transform:rotate(90deg)}
.phead:hover{background:var(--raise)}
.phead:hover .ptitle{color:var(--accent)}
.ptitle{font-weight:600;letter-spacing:-.01em;flex:1 1 18rem;min-width:0;font-size:.97rem}
.counts{display:flex;gap:.35rem;flex-wrap:wrap}
.c{font-size:.72rem;color:var(--muted);border:1px solid var(--line);border-radius:3px;
  padding:.15rem .42rem;white-space:nowrap}
.c b{font-weight:600;color:var(--ink);font-variant-numeric:tabular-nums}
.c.ok b{color:var(--ok)} .c.run b{color:var(--accent)} .c.wait b{color:var(--signal)}
.tag{font-size:.65rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);
  background:var(--sunk);border-radius:3px;padding:.14rem .38rem;white-space:nowrap}
.body{padding:0 .95rem .9rem;border-top:1px solid var(--line)}

/* Finished projects: sunk below a divider, desaturated, and labelled. Still fully
   readable when expanded — dimming the summary, not the contents. */
.sep{font-size:.66rem;text-transform:uppercase;letter-spacing:.11em;color:var(--dim);
  font-weight:600;margin:.9rem 0 -.35rem;display:flex;align-items:center;gap:.6rem}
.sep::after{content:"";flex:1;height:1px;background:var(--line)}
.proj.fin{background:transparent;box-shadow:none;border-style:dashed}
.proj.fin .ptitle{color:var(--muted);font-weight:500}
.proj.fin .phead{opacity:.8}
.proj.fin[open] .phead{opacity:1}
.c.q{color:var(--signal);border-color:color-mix(in srgb,var(--signal) 40%,var(--line))}
.c.q b{color:var(--signal)}
.c.note{color:var(--dim);border-style:dashed}
.c.note b{color:var(--muted)}
.c.done-tag{color:var(--ok);border-color:color-mix(in srgb,var(--ok) 45%,var(--line));
  background:color-mix(in srgb,var(--ok) 9%,transparent);font-weight:600}

.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:.86rem;min-width:min(100%,33rem)}
th{text-align:left;font-size:.64rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);font-weight:500;padding:.7rem .45rem .35rem;
  border-bottom:1px solid var(--line);white-space:nowrap}
th.r,td.r{text-align:right}
th:not(:first-child),td:not(:first-child){width:1%;white-space:nowrap}
th:first-child,td:first-child{width:auto}
td{padding:.4rem .45rem;vertical-align:baseline;
  border-bottom:1px solid color-mix(in srgb,var(--line) 55%,transparent)}
tbody tr:last-child td{border-bottom:0}
tr.flight td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
.tid{color:var(--dim);font-size:.74rem;margin-right:.4rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
td:first-child{overflow-wrap:break-word}
.tbtn{background:none;border:0;padding:0;font:inherit;color:inherit;text-align:left;
  border-bottom:1px dotted var(--dim);border-radius:0}
.tbtn:hover{color:var(--accent);border-color:var(--accent)}
.promote{font-size:.68rem;padding:.14rem .4rem;margin-left:.4rem}
/* The Q count is a button only when there is something to ask about. Its TEXT is
   never on this page — the allowlist forbids question text, and AWAITING.md has it. */
.qbtn{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem;font-weight:600;
  color:var(--signal);border-color:color-mix(in srgb,var(--signal) 45%,var(--line));
  background:color-mix(in srgb,var(--signal) 10%,transparent);padding:.1rem .45rem;
  font-variant-numeric:tabular-nums}
.qs{display:inline-flex;gap:.2rem}
.qbtn:hover{border-color:var(--signal);background:color-mix(in srgb,var(--signal) 18%,transparent)}
button.ghost{font-size:.72rem;padding:.28rem .5rem;color:var(--muted)}
.deps{white-space:normal!important}
button.dep{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.74rem;
  padding:.08rem .35rem;color:var(--muted);background:var(--sunk);border-color:transparent;
  font-variant-numeric:tabular-nums}
button.dep:hover{color:var(--accent);border-color:var(--accent);background:transparent}
.state{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  white-space:nowrap}
.state.ok{color:var(--ok)} .state.signal{color:var(--signal)}
.state.stop{color:var(--stop)} .state.accent{color:var(--accent)}
.dim{color:var(--dim)} .sig{color:var(--signal);font-weight:500}
td.r,td.dim{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent;
  white-space:nowrap;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a:hover,td a:focus-visible{border-bottom-color:currentColor}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

.toast{position:fixed;left:50%;bottom:1.3rem;transform:translateX(-50%);z-index:9;
  background:var(--ink);color:var(--ground);font-size:.83rem;padding:.55rem .9rem;
  border-radius:5px;box-shadow:var(--shadow);max-width:calc(100vw - 2rem);
  opacity:0;pointer-events:none;transition:opacity .18s}
.toast.on{opacity:1}
footer{border-top:1px solid var(--line);padding-top:.9rem}
footer p{margin:0 0 .5rem;font-size:.76rem;color:var(--dim);max-width:45rem}
footer p:last-child{margin:0}
code{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.93em}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>"""

TABLE_SCRIPT = r"""<script>
// The ONLY scripted behaviour: put a button's text on the clipboard. Everything
// else — layout, collapse, links — is markup and CSS, so scripting off costs the
// page nothing but this.
(function(){
  var el;
  function toast(m){
    if(!el){ el=document.createElement('div'); el.className='toast'; document.body.appendChild(el); }
    el.textContent=m; el.classList.add('on');
    clearTimeout(toast.t); toast.t=setTimeout(function(){ el.classList.remove('on'); },3000);
  }
  document.addEventListener('click', function(e){
    var b = e.target.closest ? e.target.closest('[data-copy]') : null;
    if(!b) return;
    e.preventDefault();
    var text = b.getAttribute('data-copy'), what = b.getAttribute('data-what') || 'Text';
    var ok = function(){ toast(what + ' copied — paste it to Claude'); };
    var bad = function(){ toast('Copy failed. Select this instead: ' + text); };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(text).then(ok, legacy);
    } else { legacy(); }
    function legacy(){
      try{
        var ta=document.createElement('textarea'); ta.value=text;
        ta.style.position='fixed'; ta.style.top='-1000px'; document.body.appendChild(ta);
        ta.select(); var done=document.execCommand('copy'); document.body.removeChild(ta);
        done ? ok() : bad();
      }catch(err){ bad(); }
    }
  });
})();
</script>"""


def short_ref(slug, tid):
    """`ai-bridge-v3/tasks/task-005` — what a human pastes back.

    Drops `projects/` (constant, so it carries no information) and `.md` (the
    document type is never in question). KEEPS `tasks/`: a project also holds
    `phases/`, `sources/` and `deliverables/`, so this segment is the one that says
    which kind of document is meant, and it costs six characters. The `task-` prefix
    makes it technically redundant today — but only while tasks are the only thing
    with a copy button.
    """
    return "%s/tasks/%s" % (slug, tid)


def task_number(tid):
    """Just the number — `task-003-some-slug` -> `003`.

    Falls back to the id with `task-` stripped when there is no number to find, so an
    id that does not follow the convention still renders something identifiable rather
    than an empty cell.
    """
    m = re.match(r"^task-0*(\d+)", tid or "")
    if m:
        return m.group(1).zfill(3)
    return (tid or "")[5:] if (tid or "").startswith("task-") else (tid or "")


def explain(verb, p, t, hint):
    """One short paragraph saying what this verb means and why THIS item is here.

    Composed from the verb plus counts the snapshot already carries — never from a
    task description, a document body, or the text of a question or blocker, none
    of which the snapshot forwards. So this adds no field to the published-page
    allowlist. Kept under ~280 characters on purpose: enough to act on, short
    enough to read without deciding to read it.
    """
    ts = [todict(x) for x in tolist(p.get("tasks"))]
    ph = todict(p.get("phase_progress"))
    nd = sum(1 for x in ts if x.get("status") == "done")
    nc = sum(1 for x in ts if x.get("status") == "cancelled")
    if verb == "close":
        bits = "%d done" % nd + (", %d cancelled" % nc if nc else "")
        phase = (", %d/%d phases complete" % (toint(ph.get("done")), toint(ph.get("total")))
                 if toint(ph.get("total")) else "")
        return ("Every task here has finished (%s%s), so there is nothing left to build. "
                "Closing rolls the project up, drops it off the active list and proposes "
                "marking its objective achieved. Nothing is deleted — run %s."
                % (bits, phase, hint or "/close-project"))
    if verb == "approve":
        return ("A draft is never dispatched. This one has been refined and its acceptance "
                "criteria are written, so it is waiting on you to promote it to ready — "
                "after which an agent can pick it up. Approving does not start work "
                "immediately; the next loop tick does.")
    if verb in ("answer", "question"):
        qs = [str(q) for q in tolist(t.get("open_question_text"))]
        if qs:
            # An escalated concern is prefixed `advisor:` by the project-manager. Say
            # once, in prose, where it came from — then strip the marker, so the
            # question does not read "Q1: advisor: …".
            def strip(q):
                return q[len("advisor:"):].lstrip() if q.lower().startswith("advisor:") else q
            escalated = any(q.lower().startswith("advisor:") for q in qs)
            lead = ("The advisor raised this and the project-manager could not settle it from "
                    "the documents, so it came to you. ") if escalated else ""
            body = "  ".join("Q%d: %s" % (i, strip(q)) for i, q in enumerate(qs, 1))
            return lead + body + ("  — an unanswered question blocks promotion, so the "
                                  "loop will not dispatch this task.")
        # No text carried (the default) — fall through to the count wording.
        n = toint(t.get("open_questions"))
        one = n == 1
        return ("There %s %d open question%s on this task, and an unanswered question blocks "
                "promotion — the loop will not dispatch it. The board never carries question "
                "text; use the Q button in the task table to copy a prompt that opens "
                "%s, or read AWAITING.md, which does carry %s."
                % ("is" if one else "are", n, "" if one else "s",
                   "it" if one else "them", "it" if one else "them"))
    if verb == "merge":
        prs = [todict(x) for x in tolist(t.get("prs"))]
        nums = ", ".join("#%s" % x.get("number") for x in prs)
        one = len(prs) == 1
        return ("The work is built and its pull request%s open and reviewed. It needs your "
                "merge — agents deliberately do not merge their own work."
                % (" (%s) is" % nums if one else
                   ("s (%s) are" % nums if nums else "s are")))
    if verb == "unblock":
        return ("An agent stopped because something outside its control is in the way — a "
                "missing credential, a failing dependency, a decision it cannot make. The "
                "task document records what. It will not retry until you clear it.")
    return ("This item is waiting on a human decision. The task document has the detail; "
            "the board deliberately does not carry it.")


def render_table():
    groups = [s.get("group", "?") for s in instances]
    if len(groups) == 1:
        name = groups[0].split(".")[0].replace("-", " ").replace("_", " ").title()
        title = "%s Bridge Board" % name
    else:
        title = "Bridge Board"

    rows, asks = [], []
    n_tasks = n_done = 0
    for s in instances:
        g = s.get("group", "?")
        for p in tolist(s.get("projects")):
            p = todict(p)
            ts = [todict(t) for t in tolist(p.get("tasks"))]
            # "Done" is all-tasks-terminal, or the project saying so. A project with no
            # tasks yet is NOT done — it has not started.
            done_proj = bool(p.get("status") == "done" or (
                ts and all(t.get("status") in ("done", "cancelled") for t in ts)))
            rows.append((g, p, done_proj))
            for t in ts:
                n_tasks += 1
                if t.get("status") == "done":
                    n_done += 1
                if t.get("awaiting"):
                    asks.append((g, p, t, None))
                elif t.get("open_questions"):
                    # A question only produces an `awaiting` verb while the task is a
                    # DRAFT (write-snapshot.sh, `case draft)`), so a question on a
                    # ready or in-progress task is invisible in the queue. Surfacing
                    # it here fixes that at the presentation layer, without touching
                    # the AWAITING.md contract that awaiting-queue.test.sh pins.
                    asks.append((g, p, dict(t, awaiting="question"), None))
            if p.get("awaiting_close"):
                asks.append((g, p, {"awaiting": "close", "title": "all tasks terminal",
                                    "id": ""}, "/close-project " + str(p.get("slug") or "")))

    # Finished projects sink to the bottom; among themselves and among the live ones
    # the snapshot's order is preserved, so the list does not reshuffle between renders.
    rows.sort(key=lambda r: r[2])

    head = [TABLE_HEAD.replace("__TITLE__", e(title))]
    o = ['<div class="board">']

    o.append('<header class="mast"><div><h1>%s</h1>' % e(title))
    stamps = sorted(str(s.get("generated_at") or "") for s in instances if s.get("generated_at"))
    if stamps:
        o.append('<p class="sub">Snapshot %s UTC</p>'
                 % e(stamps[-1].replace("T", " ").replace("Z", "")))
    o.append("</div><dl class=\"tally\">")
    o.append('<div><dt>Projects</dt><dd>%d</dd></div>' % len(rows))
    o.append('<div><dt>Done</dt><dd>%d/%d</dd></div>' % (n_done, n_tasks))
    o.append('<div class="%s"><dt>Awaiting you</dt><dd>%d</dd></div>'
             % ("live" if asks else "", len(asks)))
    o.append("</dl></header>")

    for d, msg in broken:
        o.append('<div class="snapnote"><strong>Unreadable snapshot.</strong> '
                 '<code>%s/SNAPSHOT.json</code> could not be parsed, so that instance is '
                 'not on the board. Re-run <code>scripts/write-snapshot.sh</code> there. '
                 '<br>%s</div>' % (e(d), e(msg)))

    # ---- the decision rail: one click copies a complete prompt --------------
    if asks:
        o.append('<section class="rail"><h2>Awaiting you</h2><ul>')
        for g, p, t, hint in asks:
            what = (t.get("id") + " (" + str(t.get("title") or "") + ")") if t.get("id") else str(t.get("title") or "")
            where = g + " › " + str(p.get("title") or "")
            o.append('<li class="ask"><details class="why"><summary class="line">'
                     '<span class="verb">%s</span><span class="what">%s</span>'
                     % (e(t.get("awaiting")), e(t.get("title"))))
            o.append('<span class="where">%s%s</span></summary>'
                     % (e(where), " · <code>%s</code>" % e(hint) if hint else ""))
            o.append('<p>%s</p></details>' % e(explain(t.get("awaiting"), p, t, hint)))
            o.append('<div class="acts">')
            if t.get("id"):
                ref = short_ref(str(p.get("slug") or ""), t["id"])
                o.append('<button class="ghost" data-copy="%s" data-what="Task reference">'
                         "copy task ref</button>" % e(ref))
                for i in range(1, toint(t.get("open_questions")) + 1):
                    o.append('<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                             'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                             "answer Q%d</button>"
                             % (e("%s Q%d: " % (ref, i)), i, e(ref), i, i))
            for verdict, (label, cls, lead) in ([] if t.get("awaiting") == "question"
                                                else WORDING.items()):
                msg = '%s Re the "%s" item on %s in %s.' % (lead, t.get("awaiting"), what, where)
                if verdict == "approve" and hint:
                    msg += " Run %s." % hint
                elif verdict == "discuss":
                    msg += " Tell me the trade-off you see and what you recommend."
                elif verdict == "reject":
                    msg += " Record why on the task and move on."
                o.append('<button class="%s" data-copy="%s" data-what="%s">%s</button>'
                         % (cls, e(msg), e(label + " prompt"), e(label)))
            o.append("</div></li>")
        o.append("</ul></section>")

    # ---- one <details> per project, collapsed by default -------------------
    n_fin = sum(1 for r in rows if r[2])
    for idx, (g, p, fin) in enumerate(rows):
        if fin and (idx == 0 or not rows[idx - 1][2]):
            o.append('<h2 class="sep">Finished · %d</h2>' % n_fin)
        tasks = [todict(t) for t in tolist(p.get("tasks"))]
        nd = sum(1 for t in tasks if t.get("status") == "done")
        nr = sum(1 for t in tasks if t.get("status") in RUNNING)
        nw = sum(1 for t in tasks if t.get("status") in PENDING)
        ph = todict(p.get("phase_progress"))
        o.append('<details class="proj%s"><summary class="phead">' % (" fin" if fin else ""))
        o.append('<span class="ptitle">%s</span><span class="counts">' % e(p.get("title")))
        if fin:
            o.append('<span class="c done-tag">✓ done</span>')
        o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
        if not fin:
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
        nq = sum(toint(t.get("open_questions")) for t in tasks)
        if nq:
            o.append('<span class="c q"><b>%d</b> question%s</span>'
                     % (nq, "" if nq == 1 else "s"))
        na = sum(toint(t.get("advisor_notes")) for t in tasks)
        if na:
            # Deliberately NOT in the signal colour and deliberately not in the
            # awaiting rail: an untriaged advisor concern is the loop's inbox, not
            # yours. It becomes a question only if the PM escalates it.
            o.append('<span class="c note" title="Advisor concerns the loop has not '
                     'triaged yet — not waiting on you"><b>%d</b> concern%s</span>'
                     % (na, "" if na == 1 else "s"))
        if toint(ph.get("total")):
            o.append('<span class="tag">%d/%d phases</span>'
                     % (toint(ph.get("done")), toint(ph.get("total"))))
        o.append("</span></summary>")

        o.append('<div class="body"><div class="scroll"><table><thead><tr>'
                 "<th>Task</th><th>State</th><th>Role</th><th>Depends on</th>"
                 "<th class=\"r\">Q</th><th>PR</th>"
                 "</tr></thead><tbody>")
        for t in tasks:
            tid = str(t.get("id") or "")
            short = tid[5:] if tid.startswith("task-") else tid
            st = str(t.get("status") or "")
            o.append('<tr%s>' % (' class="flight"' if t.get("in_flight") else ""))
            o.append('<td><span class="tid">%s</span>' % e(short))
            o.append('<button class="tbtn" data-copy="%s" data-what="Task reference">%s</button>'
                     % (e(short_ref(str(p.get("slug") or ""), tid)), e(t.get("title"))))
            if st == "draft":
                promo = ("In the ai-bridge instance, promote %s from draft to ready: review its "
                         "acceptance criteria, tighten any that are not testable, then set "
                         "status: ready." % short_ref(str(p.get("slug") or ""), tid))
                o.append('<button class="promote" data-copy="%s" data-what="Promotion prompt">'
                         "promote → ready</button>" % e(promo))
            o.append("</td>")
            o.append('<td><span class="state %s">%s</span></td>' % (TONE.get(st, ""), e(st)))
            o.append('<td class="dim">%s</td>' % e(t.get("assignee") or "—"))
            deps = [str(d) for d in tolist(t.get("depends_on"))]
            if deps:
                # Show the short id, the same form the Task column shows, and copy the
                # full bundle-relative path — a dependency is most useful as a thing to
                # go read.
                o.append('<td class="deps">%s</td>' % ", ".join(
                    '<button class="dep" data-copy="%s" data-what="Path" title="%s">%s</button>'
                    % (e(short_ref(str(p.get("slug") or ""), d)), e(d),
                       e(task_number(d))) for d in deps))
            else:
                o.append('<td class="dim">—</td>')
            q = toint(t.get("open_questions"))
            if q:
                # One handle per question. The snapshot carries only a COUNT, and
                # SCHEMA.md requires every entry to be numbered Q1, Q2, … — so the
                # labels are derivable without ever carrying question text. See the
                # caveat in the footer: this assumes the numbering starts at 1 and is
                # contiguous, which the schema asks for but does not enforce.
                ref = short_ref(str(p.get("slug") or ""), tid)
                o.append('<td class="r"><span class="qs">%s</span></td>' % "".join(
                    '<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                    'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                    'Q%d</button>' % (e("%s Q%d: " % (ref, i)), i,
                                      e(ref), i, i)
                    for i in range(1, q + 1)))
            else:
                o.append('<td class="r dim">—</td>')
            # The http/https rule applies here too: a PR URL is a link only on that
            # scheme, and anything else is inert text. This layout used to write the
            # URL straight into the href — one of the two hardening rules the second
            # script did not carry (see the header).
            cells = []
            for x in (todict(x) for x in tolist(t.get("prs"))):
                u = href(x.get("url"))
                if u:
                    cells.append('<a href="%s" target="_blank" rel="noopener noreferrer">#%s</a>'
                                 % (e(u), e(x.get("number"))))
                else:
                    cells.append('<span class="dim">#%s (link withheld: not http/https)</span>'
                                 % e(x.get("number")))
            o.append('<td>%s</td></tr>' % (" ".join(cells) if cells
                                           else '<span class="dim">—</span>'))
        o.append("</tbody></table></div></div></details>")

    o.append('<footer><p>Derived from each instance’s <code>SNAPSHOT.json</code> and '
             "<strong>as sensitive as the task documents it comes from</strong>. Titles are "
             "human-written free text; no customer PII belongs in a task title, and so none "
             "belongs here. Task descriptions, document bodies, question and blocker text, "
             "author identity and out-of-bundle paths are never carried.</p>"
             "<p>A browser cannot open a local file, so a task copies its <em>bundle-relative</em> "
             "path for you to paste — prefix it with your instance directory. Decision "
             "buttons copy a prompt; the bundle, not this page, is where a decision is "
             "recorded.</p></footer></div>")
    o.append(TABLE_SCRIPT)
    return head, o


# ---------------------------------------------------------------- write it out
if LAYOUT == "table" and not instances:
    # Publishing an empty page is not useful, so this layout writes nothing at all —
    # unlike `columns`, whose empty-state note tells a local reader how to get on the
    # board. Exit 0 either way: an instance off the board is a choice, not an error.
    print("build-board: no readable snapshot; nothing written.", file=sys.stderr)
    sys.exit(0)

head, parts = render_table() if LAYOUT == "table" else render_columns()

head_html = "\n".join(head)
body_html = "\n".join(parts)
if STANDALONE:
    doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
           + head_html + "\n</head>\n<body>\n" + body_html + "\n</body>\n</html>\n")
else:
    doc = head_html + "\n" + body_html + "\n"
OUT.write_text(doc, encoding="utf-8")
print(f"build-board: wrote {OUT} ({LAYOUT}) — {len(instances)} instance(s), "
      f"{len(awaiting)} awaiting, {len(broken)} unreadable snapshot(s).")
PY
