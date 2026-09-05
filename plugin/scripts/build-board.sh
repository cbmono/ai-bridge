#!/usr/bin/env bash
#
# build-board.sh — render every instance's SNAPSHOT.json as ONE self-contained HTML
# page: projects collapsed to one summary line, each expandable to its task table and
# its own decision rail. A page a teammate opens on a phone.
#
# THE DECISION RAIL IS PER PROJECT, AND THE COLLAPSED LINE CARRIES ITS WEIGHT. It was
# one pooled list above every project until 2026-08-30. At sixteen live projects that
# list stopped being scannable — the section that exists to say what needs you is the
# section you skip — so each project's items moved INSIDE that project, above its task
# table, holding only its own.
#
# That move is only safe because of what replaces it. Sixteen collapsed rows with the
# queues hidden inside them is STRICTLY WORSE than the clutter it removes: the clutter
# was at least honest about which projects wanted you. So the summary line carries the
# signal, and "can I tell, from the collapsed view alone, exactly which projects need
# me?" is the question this design answers. THE WEIGHTING, in full — it is three
# reinforcing channels for one number, not decoration:
#   · the COUNT itself — `<b>N</b> awaiting you`, the number of that project's rail
#     items, so the same N the pooled list would have shown for it. It is the ONLY
#     count pill in the signal colour, and since 2026-08-31 the only pill on the line
#     about attention at all: an outlined `N questions` counter used to sit beside it
#     measuring an overlapping thing, and this one now holds that pill's slot and
#     treatment (see `.c.you` in the CSS for what the merge gave up and why);
#   · a signal border and inset bar on the WHOLE CARD (`.proj.wants`) — visible at any
#     scroll position, and to a reader who never looks at a row of chips;
#   · ORDER — a project with items sorts above one without, inside its own half of the
#     board (live above, finished below), the snapshot's order preserved within each.
# A project with nothing waiting gets none of the three. Colour alone would fail a
# reader who cannot see it; the count and the order do not depend on it.
#
# THE ✕ COPIES A COMMAND. IT NEVER CLOSES ANYTHING. Closing a project is
# `/close-project`, a human-run command with its own consolidation, log entry and
# folder removal (SCHEMA.md); nothing on a rendered page may perform any of that, and
# this page has no way to. The control is a `[data-copy]` button on the SAME clipboard
# helper every other copy button uses — it writes `/close-project <slug>` to the
# clipboard and nothing else, has no href, no form and no target, and its tooltip says
# it copies a command rather than that it closes the project. Do not reword it into
# "close this project", and do not give it any behaviour beyond the copy.
#
# THE PAGE IS PER OWNER, AND HAS TWO HALVES. Your own projects come from this clone's
# SNAPSHOT.json, as they always did. Every OTHER owner's come from the tracked task
# documents at your current git HEAD, named and collapsed below them. Why it is shaped
# that way, and why it is not a shared board, is the "OTHER OWNERS" block further down.
#
#   Usage:
#     build-board.sh [--out FILE] [--standalone] [INSTANCE_DIR ...]
#     build-board.sh --list-instances [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render. With none given, the list comes
#                       from `boardInstances` in ./instance.config.local.json, else
#                       ./instance.config.json; if that key
#                       is absent or empty, just this instance.
#     --out FILE        where to write (default: ./board.html — it is the path an
#                       instance's .gitignore already covers)
#     --standalone      wrap the output in <!doctype html>/<head> for opening in a
#                       browser directly. PASS IT unless something else supplies that
#                       wrapper — watch-board.sh and the /pm-loop tick both do, and the
#                       publish step that could not is deleted. Wrapping, not markup:
#                       the same page either way, so omitting it leaves a fragment to
#                       embed, which is all the default is for now.
#     --list-instances  print the resolved instance directories, one per line, and
#                       exit without writing anything. This exists so watch-board.sh
#                       can learn WHICH directories to watch without carrying a third
#                       copy of the discovery rule below — one script owns it.
#
# WHY ONE SCRIPT WITH ONE LAYOUT — AND WHY THE OTHER ONE IS GONE RATHER THAN OFF.
# This file has been all three shapes, in this order:
#   1. two scripts — this one and a `build-artifact-board.sh`, 1,139 lines between them,
#      reading the same snapshot contract and differing only in markup. Two files meant
#      two copies of the parts a board must not get wrong, and the second copy was the
#      weaker one: it wrote a PR URL into an `href` without checking its scheme and read
#      every count with a bare `.get()`, so both hardening rules below lived in one file
#      and not the other.
#   2. one script, two layouts, `--layout` choosing the markup. That fixed the
#      duplication and left a new problem in its place: a DEFAULT. Every caller now had
#      to remember the flag, and the /pm-loop tick published with `--layout table` while
#      watch-board.sh forwarded no layout at all — so the local live page and the
#      published page were two different boards rendered by one script, and nothing in
#      the code said so.
#   3. one script, one layout. The owner saw both rendered from live data and rejected
#      the kanban `columns` page outright — "not necessary and it's not usable, it's just
#      not readable" — so it is DELETED: markup, CSS, its queue derivation and its tests.
#      Not defaulted away. A rejected path kept behind a flag is still maintained, still
#      tested, and still one forgotten argument away from being what a human sees; the
#      inconsistency in (2) is exactly that failure, and only deletion closes it by
#      construction. `--layout` is now refused BY NAME (see the arg loop), so a caller
#      written against (2) fails loudly instead of silently getting the other page.
# The rule this file keeps paying for: a second rendering path is a second place for a
# hardening rule to be missing. Do not add one back without deleting this paragraph.
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
# of it authored here. This is the same boundary session-banner.sh keeps when it
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
# WHAT THIS PAGE DOES AND DOES NOT CARRY. These were once "the table layout's"
# properties as opposed to the other one's; they are now simply the board's, and every
# test that reads them reads them off the only page there is.
#   · It uses <details>, never script, for collapsing. The first version rendered from
#     JavaScript and toggled with a click handler; two bugs came out of that and NEITHER
#     WAS DIAGNOSABLE IN PLACE, because the artifact host serves the page in an iframe
#     that exposes neither its console nor its accessibility tree, so a blank page had no
#     error to read. <details> needs no script, works with scripting off, is
#     keyboard-accessible for free, and its open/closed state is per-viewer.
#   · It DOES carry one <script> and one external <link>: a clipboard helper (a browser
#     cannot open a local file, so a task copies a SHORT REFERENCE — `<project>/tasks/<id>`
#     — instead of a link, and every button says what it copied so a failed copy is
#     visible rather than silent) and a webfont stylesheet. Nothing from a snapshot ever
#     reaches either of them; the escaping rules above are what hold, not "no script". A
#     retained project's deliverables panel copies with this SAME helper, and so does the
#     ✕ close-command control — every `[data-copy]` button on the page shares it, and
#     there is no second one.
#   · A FAILED COPY IS A STICKY, SELECTABLE FAILURE — because the page is opened over
#     `file://`. The tick renders to `.board-live/board.html` and a human double-clicks
#     it, so the copy buttons have to work on an origin nobody serves.
#     WHAT WAS ACTUALLY MEASURED THERE, on `file:///…/board.html` in Chrome 151 (macOS),
#     because the intuition was wrong in a way worth writing down: `file:` IS a
#     potentially trustworthy origin in Chromium — `window.isSecureContext` is **true**
#     and `navigator.clipboard` is an **object**, not `undefined`. The async path is
#     the one that runs, and a real click on the ✕ put `/close-project <slug>` on the
#     system clipboard. So the fallback is not load-bearing for Chrome-on-file:// and
#     must not be described as if it were. It stays because the async call can still be
#     REFUSED — an unfocused document, a browser that does not extend trust to `file:`,
#     a denied permission — and that was measured too: with `writeText` forced to
#     reject, `document.execCommand('copy')` carried the same click through to the same
#     clipboard.
#     WHEN BOTH ARE REFUSED the toast STAYS UP, turns `user-select:text;
#     pointer-events:auto`, carries the exact text in a `<code>` (`user-select:all`) and
#     has to be dismissed. Deliberately not a three-second message: a control that
#     appears to copy and does not is worse than no control, and a failure notice that
#     fades before you can select it is that same defect one step removed. Do not
#     restore auto-hide on the failure path.
#   · A retained project's deliverables panel is built from `deliverable_paths:` in the
#     project's own SNAPSHOT.json stanza — which write-snapshot.sh reads from
#     project.md's frontmatter, and ONLY from there. This renderer never opens `tasks/`
#     and never lists `deliverables/` from disk; that is what keeps it compatible with
#     the done-project skip (see write-snapshot.sh's header). Every entry is re-checked
#     against `/projects/<slug>/deliverables/<file>` (bundle_deliverable()) before it can
#     reach a button — so every DELIVERABLE path on this page resolves inside that
#     project's own `deliverables/`, a NESTED file below it included (an exported site's
#     `site/index.html`), which is inside the guarantee and rendered, not dropped. Scoped
#     to deliverables and no wider ON PURPOSE: this page renders a `/projects/<slug>/`
#     from an unvalidated slug elsewhere (the other-owners section), which this check
#     does not cover and does not claim to.
#   · THE ONE THING IT READS OFF DISK THAT IS NOT A SNAPSHOT: `projects/<slug>/project.md`,
#     for its `timestamp:` and for nothing else, to put a creation date on the collapsed
#     line. This is not a new source — it is the SAME document the other-owners section
#     already reads, from the working tree instead of from HEAD, which is the right side
#     for a project that is YOURS (the snapshot beside it is derived from that same tree).
#     Three limits keep it inside the published-page rules: the slug must be one
#     well-formed segment (DELIV_SEG) before it can be joined to a path, so a snapshot
#     claiming `"slug": ".."` reads nothing; only a strict leading `YYYY-MM-DD` is taken
#     from the value, so a trailing YAML comment, an absolute path or any other text on
#     that line cannot reach the page; and an absent, unreadable or unparseable
#     project.md renders no date at all rather than an error. Do not widen this to read
#     any other field — every other field a board needs comes through write-snapshot.sh's
#     allowlist, on purpose.
#   · Its decision rail surfaces one thing AWAITING.md does not: an open question on a
#     task that is no longer a draft. write-snapshot.sh only emits an `awaiting` verb for
#     a question while the task IS a draft, so such a question is invisible in the queue;
#     the rail adds it at the presentation layer, without touching the AWAITING.md
#     contract that awaiting-queue.test.sh pins. It surfaces it only while the task is
#     LIVE: a `done`/`cancelled` task contributes nothing to the rail, because the
#     paragraph the rail writes for such an item ("an unanswered question blocks
#     promotion") is not true of a task that already shipped, and answering it clears
#     nothing on this page — a queue you cannot empty by doing what it asks is the one
#     people stop reading. A project's own `awaiting_close` is unaffected.
#   · A QUESTION IS LABELLED BY THE `Q<n>` IT CARRIES, NEVER BY ITS POSITION. The labels
#     used to be `range(1, open_questions + 1)`, which is a position dressed as a name:
#     a task whose Q1 was answered and whose Q2 is open rendered `answer Q1`, pointing a
#     human at the wrong question in a document they then stop trusting. The number is
#     read out of the question's own text (q_split), and where there is no number to
#     read — question text not published, or an entry with no `Qn` prefix — the control
#     renders unnumbered and says why. There is no positional fallback anywhere in this
#     file, and reintroducing one is reintroducing the defect.
#   · With no readable snapshot it writes NOTHING and exits 0. Publishing an empty board
#     is not useful, and an instance off the board is a choice, not an error.
#
# Deterministic. No network at build time — the only subprocess is a local `git` read for
# the other-owners section, described below. Verified by tests/snapshot.test.sh (the
# writer, plus this renderer's data-governance boundary), tests/artifact-board.test.sh
# (this renderer's markup and hardening), tests/per-owner-board.test.sh (the two-section
# split and its HEAD keying), tests/board-renderers.test.sh (print-board and watch-board)
# (this file's size).
set -euo pipefail

OUT="board.html"
STANDALONE=0
LIST_ONLY=0
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "build-board: --out needs a path" >&2; exit 2; }; OUT="$1" ;;
    --out=*) OUT="${1#--out=}" ;;
    # The tombstone. --layout is gone (see the header), and a caller that still
    # passes it is refused BY NAME rather than by the generic unknown-flag line
    # below: every such caller was written when the flag chose between two pages, so
    # "unknown flag" would leave a human wondering which page they are now getting.
    --layout|--layout=*) echo "build-board: --layout was removed — there is only one board now. Drop the flag." >&2; exit 2 ;;
    --standalone) STANDALONE=1 ;;
    --list-instances) LIST_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "build-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done
command -v python3 >/dev/null 2>&1 || {
  echo "build-board: needs python3 (standard library only). See this script's header for why." >&2
  exit 2
}

BOARD_OUT="$OUT" BOARD_STANDALONE="$STANDALONE" BOARD_LIST_ONLY="$LIST_ONLY" \
  python3 - "${DIRS[@]+"${DIRS[@]}"}" <<'PY'
import html, json, os, re, subprocess, sys, time, unicodedata
from pathlib import Path

OUT = Path(os.environ["BOARD_OUT"])
STANDALONE = os.environ.get("BOARD_STANDALONE") == "1"


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

# `inst_dirs` runs parallel to `instances`: the second section needs the DIRECTORY (to
# read its git HEAD and its config), while the snapshot itself must never carry a path.
# Kept as a separate list rather than a key on the parsed data, so there is no way for a
# filesystem path to be picked up by something that walks the snapshot's own fields.
instances, inst_dirs, broken = [], [], []
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
    inst_dirs.append(d)

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

# ---------------------------------------------------------------- the board
TONE = {"blocked": "stop", "review": "signal", "in-review": "signal",
        "done": "ok", "in-progress": "accent"}
PENDING = ("draft", "ready", "blocked")
RUNNING = ("in-progress", "in-review", "review")
TERMINAL = ("done", "cancelled")

# ---------------------------------------------------------------- other owners
#
# WHY THERE IS A SECOND SECTION AT ALL, AND WHY IT IS NOT A SECOND SNAPSHOT.
#
# Artifact publishing is ACCOUNT-SCOPED: the update path needs an artifact the account
# owns, and no share level grants it, so exactly one account can ever publish to a given
# URL. Two humans sharing a bundle therefore cannot share one published board — each
# publishes their own, to their own URL — and a board that shows only its owner's work is
# half a board. The cross-owner half has to come from something both clones actually
# have.
#
# THAT IS GIT, AND ONLY GIT. `SNAPSHOT.json` is gitignored and untracked, so no clone
# ever holds another clone's; reaching for one would read a file that is never there.
# `projects/*/project.md` and `projects/*/tasks/*.md` ARE tracked. Reading those is also
# one derivation closer to the source of truth than a snapshot is, and reading them at
# HEAD rather than from the working tree means the section shows what you have PULLED —
# never your own uncommitted edits to a document you do not own.
#
# KEYED TO THE SHA, NOT TO A CLOCK. The instinct here was a 15- or 30-minute refresh, and
# it is the wrong primary trigger in both directions: this section can only change when
# HEAD moves, so a timer re-reads for nothing every minute you do not pull and shows a
# stale section the moment you do. The SHA is exact, free to read and cheap to compare.
# The wall clock survives as a FALLBACK for one case only, described at `others_for`.
#
# THE OWNERS ARE NAMED, ON A PAGE THAT GETS PUBLISHED. That is a decision, not an
# oversight — see write-snapshot.sh's header, which now carries `owner` for exactly this,
# and /knowledge/findings/board-owner-identity-named-not-redacted.md. The section is
# collapsed by default because it is CONTEXT rather than your queue; the names are in the
# HTML whether it is open or shut, so the collapse is ergonomics and never a privacy
# control. The footer says so in as many words, because a reader who sees a closed block
# should not conclude the names are hidden.
#
# EVERYTHING READ HERE IS UNTRUSTED TEXT, exactly as a snapshot is: same human-written
# documents, arriving through git instead of through the writer. It goes through the same
# e(), it renders only bundle-relative paths, and none of it reaches a <script>.
OTHERS_CACHE = ".board-others.json"
OTHERS_SCHEMA = "ai-bridge other-owners cache v1"
OTHERS_TTL = 900          # seconds — the FALLBACK only; see others_for()


def read_obj(path):
    """A JSON object from a file, or {} — never an exception and never a non-dict.

    Same shape as the config read in resolve_dirs, and for the same reason: a file whose
    top level is a list or a string parses fine and then has no .get, and an
    AttributeError here would end the run in a traceback instead of a documented
    fallback.
    """
    try:
        v = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError, UnicodeDecodeError):
        return {}
    return v if isinstance(v, dict) else {}


def who_and_default(d):
    """(this clone's login, defaultOwner) for one instance directory.

    TWO DIFFERENT READS, on purpose, and SCHEMA.md → "Per-machine config overrides" is
    the one place that set is listed. `ownerGithubUser` answers "who is this clone?", so
    the gitignored local file wins over the tracked one — on a shared bundle a tracked
    value would make both clones claim the same identity. `defaultOwner` answers "who
    owns unowned work?", is only correct while BOTH clones agree, and is therefore read
    from the TRACKED file only: a local override there is precisely the disagreement it
    exists to prevent.
    """
    tracked = read_obj(d / "instance.config.json")
    local = read_obj(d / "instance.config.local.json")
    me = local.get("ownerGithubUser") or tracked.get("ownerGithubUser") or ""
    return str(me).strip(), str(tracked.get("defaultOwner") or "").strip()


def owner_of(p, default_owner):
    """SCHEMA.md's resolution, steps 2-4: the project's `owner:`, else `defaultOwner`,
    else nobody.

    Step 1 — a task's own `owner:` — is deliberately not applied. This board partitions
    by PROJECT, and a per-task override is a dispatch concern; honouring it here would
    split one project across two sections, which is less readable than the thing it fixes.
    """
    return str(p.get("owner") or "").strip() or default_owner


def is_mine(owner, me):
    """Unowned work is everybody's (SCHEMA.md step 4), and the comparison is
    case-insensitive, as SCHEMA.md requires.

    With no configured human (`me` empty) an OWNED project is NOT mine: this clone cannot
    prove the name is its own, which is the same refusal the dispatch gate makes. It
    still renders — under its owner, in the section below — so nothing disappears.
    """
    return not owner or owner.lower() == me.lower()


def git(d, *args):
    """One local git read, or None.

    Never raises and never blocks the render: a directory that is not a repository, a git
    that is not installed, a repository with no commits, and a call that times out are
    all "no second section", not a failed page.
    """
    try:
        r = subprocess.run(("git", "-C", str(d)) + args,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


FM_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")


def frontmatter(text):
    """The scalar frontmatter keys of an OKF document.

    Same contract as write-snapshot.sh's awk, so the two halves of the board agree on
    what "unreadable" means: a document that does not OPEN with `---`, or opens and never
    closes, yields nothing rather than a guess. Scalars only — this reads four fields
    (title, status, kind, owner) and has no business parsing lists.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fm
        m = FM_LINE.match(line)
        if not m:
            continue
        v = m.group(2).strip()
        if len(v) > 1 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]                      # one layer of quotes, as fmfield() strips
        if m.group(1) in ("status", "kind", "owner"):
            v = v.split("#")[0].strip()      # an enum's trailing comment is not the value
        fm[m.group(1)] = v
    return {}                                # opened and never closed: unreadable


def others_from_head(d, me, default_owner):
    """Every OTHER owner's projects, read from the tracked documents at this clone's HEAD.

    `-z` on the listing is load-bearing: without it git quotes any path with a non-ASCII
    or special character, and the quoted form is not a path you can hand back to
    `git show`. One `show` per document, and only for projects that turn out not to be
    this clone's — a project.md is read to learn the owner, its tasks only if the answer
    is somebody else.
    """
    listing = git(d, "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", "projects")
    if listing is None:
        return None                          # no HEAD to read: no section at all
    projects, tasks = {}, {}
    for path in listing.split("\0"):
        parts = path.split("/")
        if len(parts) == 3 and parts[2] == "project.md":
            projects[parts[1]] = path
        elif (len(parts) == 4 and parts[2] == "tasks" and path.endswith(".md")
                and parts[3] not in ("index.md", "log.md")):
            tasks.setdefault(parts[1], []).append(path)
    out = []
    for slug in sorted(projects):
        blob = git(d, "show", "HEAD:" + projects[slug])
        if blob is None:
            continue
        fm = frontmatter(blob)
        owner = owner_of(fm, default_owner)
        if is_mine(owner, me):
            continue                         # rendered above, from the snapshot
        done = running = pending = 0
        for tpath in sorted(tasks.get(slug, [])):
            tblob = git(d, "show", "HEAD:" + tpath)
            if tblob is None:
                continue
            st = frontmatter(tblob).get("status", "")
            if st in TERMINAL:
                done += 1
            elif st in RUNNING:
                running += 1
            else:
                pending += 1
        out.append({"owner": owner, "slug": slug, "title": fm.get("title") or slug,
                    "status": fm.get("status", ""),
                    "done": done, "running": running, "pending": pending})
    return out


def others_for(d, me, default_owner):
    """The section's data, cached against the HEAD SHA.

    The cache is a gitignored file in the instance directory, and it carries the identity
    it was computed FOR: a clone that changes its `ownerGithubUser` partitions the board
    differently, so a cache keyed on the SHA alone would keep answering for the old human.

    THE WALL CLOCK IS HERE, AND ONLY HERE, and it is a fallback rather than a schedule.
    When the SHA cannot be read at all — no git on the machine, a directory that is not a
    repository, a repository with no commits yet, a `.git` momentarily unavailable under a
    sync or a worktree operation, or a call that times out under load — recomputing
    returns nothing, and writing that nothing to the cache would drop every other owner
    off the published page until the next pull. So a RECENT cached answer is served
    instead, and a cache entry without a SHA is never written: an unkeyed entry is worth
    nothing to the next run. Nothing here re-reads on a timer while a SHA is available.
    """
    head = (git(d, "rev-parse", "HEAD") or "").strip()
    cache = d / OTHERS_CACHE
    hit = read_obj(cache)
    usable = (hit.get("_schema") == OTHERS_SCHEMA and isinstance(hit.get("owners"), list)
              and hit.get("me") == me and hit.get("default") == default_owner)
    if usable and head and hit.get("head") == head:
        return hit["owners"]
    if usable and not head and time.time() - toint(hit.get("at")) < OTHERS_TTL:
        return hit["owners"]
    owners = others_from_head(d, me, default_owner)
    if owners is None:
        return []
    if head:
        try:
            cache.write_text(json.dumps({"_schema": OTHERS_SCHEMA, "head": head,
                                         "me": me, "default": default_owner,
                                         "at": int(time.time()), "owners": owners}),
                             encoding="utf-8")
        except (OSError, UnicodeEncodeError):
            pass          # a read-only instance still renders; it just re-reads next time
    return owners


# ONE STRING, TWO CONTROLS. `promote → ready` in the task table and `Approve` on a
# PROMOTION item in the waiting rail are the SAME decision — "this draft is ready" — so
# they copy the same bytes, from here, instead of two spellings of one act. The button
# used to copy a three-sentence prompt ("In the ai-bridge instance, promote … from draft
# to ready: review its acceptance criteria, tighten any that are not testable, then set
# status: ready.") while the rail copied a generic `APPROVED — go ahead.` Both were
# wrong in the same way: the prompt told an agent how to do a job it already knows, and
# neither could be pasted beside the other without the reader wondering whether two
# different things had been asked for. The verb is the payload; the handle says which
# document. Nothing here performs the promotion — `status: ready` in the document is a
# human authority (SCHEMA.md), and this page only ever copies text.
PROMOTE = "promote to ready"

WORDING = {
    "approve": ("Approve", "go", "APPROVED — go ahead."),
    "discuss": ("Let’s discuss", "", "I want to discuss this before you proceed."),
    # REJECT DECLINES THE ACTION. IT DOES NOT CANCEL THE TASK, and the wording used to
    # imply that it did: `REJECTED — do not proceed. Record why on the task and move on.`
    # reads as "this one is over", so an agent receiving it could reasonably close the
    # task the owner had only said no to. Nothing on this page changes a status, a
    # rejected draft stays `draft`, and cancelling is `status: cancelled` — a different
    # act with no control here. So the payload says what it declines and what to leave
    # alone (the suffix is added in the loop below).
    "reject": ("Reject", "no", "REJECTED — do not do this."),
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

/* THE BLOCK THAT MATTERS HAS TO SEPARATE FROM THE CARD HOLDING IT. Its fill was
   `--signal` 8% on `--surface` — 1.12:1 against the card it sits in, and the card's own
   `.proj.wants` head is 7% of the same hue, so the one block on the page that says "you
   are the blocker" dissolved into its container. It is now a DEEPER, DESATURATED amber
   built on `--sunk` (the page's recessed neutral) rather than on `--surface`, so it
   reads as a panel set INTO the card: 1.42:1 in light, 1.47:1 in dark. Still one hue —
   the accent already means "needs you" everywhere here, and a second one would compete
   with it — and the amber left rail and the label stay, since those are what the eye
   finds first.
   THE LABEL MOVES WITH THE FILL. Plain `--signal` on this deeper ground is 3.93:1,
   under AA for text this small (.68rem), so it takes 22% of `--ink`: 5.22:1 in light and
   6.05:1 in dark, and still visibly amber (#7e4811 / #dfb178). Mixing toward `--ink`
   rather than toward black is what makes one rule right in both themes — `--ink` is
   dark in light mode and light in dark mode, exactly as `.c.you` does it. */
.rail{border-left:.22rem solid var(--signal);border-radius:0 6px 6px 0;
  background:color-mix(in srgb,var(--signal) 16%,var(--sunk));padding:.9rem 1rem}
.rail h2{margin:0 0 .7rem;font-size:.68rem;text-transform:uppercase;letter-spacing:.1em;
  color:color-mix(in srgb,var(--signal) 78%,var(--ink));font-weight:600}
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
/* The task filename on a waiting row. `.tid` already owns this treatment in the task
   table; the only difference here is that the flex gap supplies the separation, so its
   own right margin would double it. */
.line .tid{margin-right:0}
.verb{font:600 .64rem/1.7 "IBM Plex Mono",ui-monospace,monospace;text-transform:uppercase;
  letter-spacing:.08em;color:var(--signal);white-space:nowrap}
/* THE BREADCRUMB WAS THE LEAST LEGIBLE THING IN THE BLOCK, and it was measurably so,
   not just to taste: `--dim` on `.ask`'s surface is 3.18:1 in light and 3.79:1 in dark,
   both under AA's 4.5:1 for text this small (.75rem ≈ 12px). `--muted` is 5.98:1 and
   6.67:1 — the same grey family one step up, no new colour. */
.where{width:100%;font-size:.75rem;color:var(--muted)}
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
/* The title no longer eats the free space — the date sits immediately after it, and a
   growing title would have pushed the date to the far end again, which is where it just
   came from. `.counts` takes the space instead, so the chips stay exactly where they
   have always been: hard against the ✕ at the end of the line. */
.ptitle{font-weight:600;letter-spacing:-.01em;flex:0 1 auto;min-width:0;font-size:.97rem}
.counts{display:flex;gap:.35rem;flex-wrap:wrap;margin-left:auto}
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
/* Another owner's work: the same card, set in mono and dimmed like a finished one,
   because it is context rather than your queue. It is NOT hidden — the name is in the
   markup whether this block is open or shut; the collapse is ergonomics. */
.proj.other{background:transparent;box-shadow:none;border-style:dashed}
.proj.other .ptitle{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.9rem;
  color:var(--muted)}
.proj.other[open] .ptitle{color:var(--ink)}
/* THE AWAITING SIGNAL ON A COLLAPSED LINE. Three channels for one number, so the
   collapsed board still answers "which projects need me?" — see the header's WEIGHTING
   block. These rules sit AFTER .proj.fin/.proj.other on purpose: a finished project
   proposing its own close is exactly a project that wants you, and must not be
   quietened by the dashed, shadowless treatment above. */
.proj.wants{border-color:color-mix(in srgb,var(--signal) 55%,var(--line));
  border-style:solid;box-shadow:inset .3rem 0 0 var(--signal),var(--shadow)}
.proj.wants .phead{padding-left:1.25rem;
  background:color-mix(in srgb,var(--signal) 7%,transparent)}
.proj.wants .phead:hover{background:color-mix(in srgb,var(--signal) 13%,transparent)}
.proj.wants .ptitle{color:var(--ink);font-weight:600}
.proj.fin.wants .phead{opacity:1}
/* THE ONE PILL, IN THE SLOT AND THE TREATMENT THE `N questions` PILL HELD. There were
   two: this one, filled and first in the row, plus an outlined `N questions` at the end
   of it. Two chips for overlapping things is a chip nobody trusts, so the questions
   counter went and this one moved into its place — last of the count chips, outlined,
   signal-coloured, `.c.q`'s own rule kept and relabelled rather than a third styling
   invented. It is still the only chip on the line in the signal colour.
   The filled treatment is what this gives up. It was one of three channels (header,
   WEIGHTING); the two that do not depend on noticing a chip — `.proj.wants` on the
   whole card, and the sort — are unchanged and carry the collapsed view on their own. */
.c.you{color:var(--signal);border-color:color-mix(in srgb,var(--signal) 40%,var(--line));
  font-weight:600}
.c.you b{color:var(--signal);font-weight:700}
/* Creation date, read from project.md's `timestamp:`. Mono and tabular so a column of
   them lines up down the page. */
.pdate{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.72rem;
  color:var(--dim);font-variant-numeric:tabular-nums;white-space:nowrap;flex-shrink:0}
/* The ✕. It COPIES `/close-project <slug>` and does nothing else — see the header. */
button.pclose{font-size:.85rem;line-height:1;padding:.2rem .42rem;color:var(--dim);
  background:none;border-color:transparent;flex-shrink:0}
button.pclose:hover{color:var(--stop);border-color:var(--stop);background:var(--surface)}
/* A project's own rail, inside its body and above its task table. */
.body>.rail{margin:.85rem 0 .1rem}
/* `.c.q` — the `N questions` pill — is deliberately absent. Its slot and its treatment
   are `.c.you`'s above; there is no second counter for the same thing. */
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
/* MIDDLE, not baseline. Against a title that wraps to two lines every other cell in the
   row — the state, the dependencies, the PR link — sat pinned to the first line and read
   as if it belonged to that line rather than to the row. (An assignee cell used to be the
   clearest case; the Role column is gone, the alignment defect is not.) */
td{padding:.4rem .45rem;vertical-align:middle;
  border-bottom:1px solid color-mix(in srgb,var(--line) 55%,transparent)}
tbody tr:last-child td{border-bottom:0}
tr.flight td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
.tid{color:var(--dim);font-size:.74rem;margin-right:.4rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
td:first-child{overflow-wrap:break-word}

/* ---- THE TASK ROW: THE JITTER IS THE BUG, NOT THE LINE COUNT --------------------
   `014-banner-reaches-the-human Some title` and `001-local-board Some title` are two
   inline runs, so every title started at a different x and the whole column read as
   ragged. Worse, the row reflowed between one and two lines as the window moved, and a
   list where some rows are one line and their neighbours two is a list you re-find your
   place in on every scroll. Both are the SAME defect — nothing about the row is fixed —
   and both are fixed by giving the filename a column of its own.

   STACKED IS THE ONLY SHAPE, because it is the one that needs no measurement: `.trow` is
   a flex COLUMN, so filename is line 1 and title is line 2 on EVERY row, at EVERY width.
   Uniform by construction — there is no width at which one row can be one line and the
   next two. It was the narrow half of two layouts until 2026-08-31; the block below the
   rules says what the other half bought and why it is deleted rather than re-tuned.

   `.tfile` IS THE FILENAME LINE, AND THE PROMOTE CONTROL IS ON IT. It used to sit in
   `.tmain` above the title, which made a draft row THREE lines while every other row was
   two. Here it rides beside the filename: one line either way, so a draft row is exactly
   as tall as its neighbours. `flex-wrap:wrap` is the
   escape valve for a filename long enough to leave the control no room — the control
   drops to a line of its own rather than overflowing the column or pushing the title
   out of alignment, and only that one row grows.
   `.tmain` holds the title alone. */
.trow{display:flex;flex-direction:column;align-items:flex-start;gap:.15rem;min-width:0}
.tfile{display:flex;align-items:baseline;flex-wrap:wrap;gap:.3rem;min-width:0}
.tfile>.tid{margin-right:0;min-width:0;overflow-wrap:anywhere}
.tmain{display:flex;flex-direction:column;align-items:flex-start;gap:.22rem;min-width:0}

/* ONE LAYOUT AT EVERY WIDTH, AND THE WIDE VARIANT IS DELETED RATHER THAN NARROWED.
   A width-conditional block at 1200px used to turn `.trow` back into a row with `.tfile`
   pinned to a fixed 56-character flex basis — 39 for the longest filename in the bundle,
   2 of gutter, ~15 for the promote control — so every title started at the same x.
   It bought that alignment at a price the owner read off the rendered page: a title
   sitting ~400px to the right of its own filename, with the whitespace between them
   growing on every filename shorter than the longest one, and the eye having to travel
   the gap to pair the two halves of one row. The stacked pair reads as one thing; the
   split pair reads as two columns that happen to be adjacent.
   SO THE BREAKPOINT IS GONE, NOT RE-TUNED. A second layout is a second set of row
   metrics to keep honest — that basis was already the third number measured for it — and
   the defect it existed to fix (ragged title x-positions) is fixed by the base rule too:
   `.trow` is a flex COLUMN, so the filename is line 1 and the title is line 2 on EVERY
   row, at EVERY width, and every title starts at the same x because it starts at the
   cell's own left edge. Uniform by construction, with no width at which one row is one
   line and its neighbour two, and nothing left to re-measure when a longer filename
   arrives — `min-width:0` plus `overflow-wrap:anywhere` on `.tfile>.tid` still wrap it.
   Do not reintroduce a width-conditional row without deleting this paragraph. */
.tbtn{background:none;border:0;padding:0;font:inherit;color:inherit;text-align:left;
  border-bottom:1px dotted var(--dim);border-radius:0}
.tbtn:hover{color:var(--accent);border-color:var(--accent)}
/* THE PROMOTE CONTROL LOOKS LIKE A CONTROL AT REST. It used to be a plain grey button
   that only picked up the accent on hover — so the one row on the board asking for an
   action announced itself only to a pointer already on top of it, and to a touch screen
   never at all. The states are INVERTED: the accent outline is the resting
   appearance, and hover drops it for a filled neutral. Hover is now a state change
   ("you are on this one"), not the moment the button becomes visible. */
.promote{font-size:.68rem;padding:.14rem .4rem;margin:0;
  border-color:var(--accent);color:var(--accent);background:transparent}
.promote:hover,.promote:focus-visible{border-color:var(--ink);color:var(--ink);
  background:var(--sunk)}
/* The Q count is a button only when there is something to ask about. Its TEXT is
   never on this page — the allowlist forbids question text, and AWAITING.md has it. */
.qbtn{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem;font-weight:600;
  color:var(--signal);border-color:color-mix(in srgb,var(--signal) 45%,var(--line));
  background:color-mix(in srgb,var(--signal) 10%,transparent);padding:.1rem .45rem;
  font-variant-numeric:tabular-nums}
.qs{display:inline-flex;gap:.2rem}
.qbtn:hover{border-color:var(--signal);background:color-mix(in srgb,var(--signal) 18%,transparent)}
/* A HANDLE THE BOARD CANNOT NAME. It is drawn quieter and dashed on purpose: it does
   not know which question it is, so it must not look as authoritative as one that does.
   Its tooltip says which of the two absences produced it. What it must never do is
   borrow a number from its position in the list — see q_split(). */
.qbtn.nonum{color:var(--muted);border-style:dashed;background:transparent}
.qbtn.nonum:hover{color:var(--signal);border-color:var(--signal);background:transparent}
button.ghost{font-size:.72rem;padding:.28rem .5rem;color:var(--muted)}
.deps{white-space:normal!important}
/* THREE refs must not wrap, and they are separated by a SPACE, not by ", ". A comma
   between two pills costs a character and carries no information — the pills are
   already discrete boxes — and it was what held the target at two refs per line. So
   the width is re-derived for the pair of changes together: button.dep's own box
   (3ch of digits + .7rem of padding + 2px of border, each) times THREE, plus the two
   single-space separators between them, plus this td's own .9rem of horizontal padding
   (box-sizing:border-box counts it). Every term is read off the pill's and the td's own
   CSS, and the `ch` is well defined because this rule sets the font the cell measures
   in. The separator term is still `2ch` and that is a coincidence worth naming: it used
   to be ONE two-character `", "` between two pills, and it is now TWO one-character
   spaces between three. 4+ refs may still wrap past this width, which is the intent,
   and a single ref never sees this min-width at all. */
.deps:has(button.dep:nth-of-type(2)){font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:.74rem;min-width:calc(3*(3ch + .7rem + 2px) + 2ch + .9rem)}
/* THE PR CELL WRAPS AT TWO REFS, AND ITS WIDTH IS IN PIXELS BECAUSE IT WAS MEASURED.
   Nine PRs on one task rendered as ONE UNBROKEN LINE — 386px measured at 1400px, the
   widest thing in the table and in one of the columns nobody reads first — because
   `td:not(:first-child)` is `nowrap` and nothing capped the column. The board this was
   reported from carries ten on a row.
   WHERE 107px COMES FROM. The cell sets its own font, exactly as `.deps` does above and
   for the same reason: with one font in the cell, every character in it — the refs and
   the spaces between them — is one advance wide, and the number below is a measurement
   rather than an estimate spanning two typefaces. Nothing sets `html`'s font-size, so
   1rem is the root's 16px and .8rem is 12.8px; IBM Plex Mono's advance is 0.6em, so one
   character is 7.68px — confirmed against the rendered page, where a `#1234` link
   measures 38.41px across its five characters (7.682px each). Twelve characters is
   92.16px, which is `#1234 #1234` (eleven) with one to spare, and this td's own .9rem of
   horizontal padding is 14.4px (box-sizing:border-box counts it): 92.16 + 14.4 =
   106.56, so 107px.
   IT IS A FLOOR, AND THE FLOOR IS WHAT DOES THE WORK — `max-width` here does nothing,
   measured: `td:not(:first-child)` asks for `width:1%`, so once the cell may wrap the
   column collapses to its min-content (ONE ref, 52.78px) and a cap above that is never
   reached. `min-width` is therefore the property, exactly as `.deps` uses it, and the
   1% is what stops the column growing past it: 107 - 14.4 = 92.6px of content, which
   holds two refs and their space (84.5px) and cannot hold three (130.6px).
   ON A ROW WITH ONE REF the reservation would be width taken for nothing, so it is
   conditional on a second ref being there — again `.deps`'s shape. A five-digit repo
   (`#12345`, 46.08px) puts one ref per line rather than two: the cell wraps instead of
   overflowing, which is the property, and nothing here assumes four digits. */
td.prs{white-space:normal!important;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td.prs:has(a:nth-of-type(2)){min-width:107px}
button.dep{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.74rem;
  padding:.08rem .35rem;color:var(--muted);background:var(--sunk);border-color:transparent;
  font-variant-numeric:tabular-nums}
button.dep:hover{color:var(--accent);border-color:var(--accent);background:transparent}
.delivs{padding:.85rem .95rem 0}
.delivs h3{margin:0 0 .5rem;font-size:.64rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);font-weight:600}
.delivs ul{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:.4rem}
button.dlv{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.76rem;
  padding:.28rem .55rem;color:var(--muted);background:var(--sunk);border-color:transparent}
button.dlv:hover{color:var(--accent);border-color:var(--accent);background:transparent}
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
  display:flex;gap:.6rem;align-items:flex-start;
  background:var(--ink);color:var(--ground);font-size:.83rem;padding:.55rem .9rem;
  border-radius:5px;box-shadow:var(--shadow);max-width:calc(100vw - 2rem);
  opacity:0;pointer-events:none;transition:opacity .18s}
.toast.on{opacity:1}
/* THE FAILURE STATE, and why it is not just a red message. On a `file://` origin the
   clipboard can be refused outright, and a notice that fades after three seconds and
   cannot be selected leaves the reader with nothing — the same as a control that
   silently did nothing. So a failed copy is SELECTABLE and STAYS until dismissed. */
.toast.fail{background:var(--stop);color:var(--ground);pointer-events:auto;
  user-select:text;-webkit-user-select:text}
.toast.fail code{display:block;margin-top:.3rem;padding:.2rem .35rem;font-size:.86em;
  background:rgba(0,0,0,.28);border-radius:3px;word-break:break-all;
  user-select:all;-webkit-user-select:all}
.toast .x{display:none}
.toast.fail .x{display:block;flex-shrink:0;background:none;border-color:transparent;
  color:var(--ground);font-size:1rem;line-height:1;padding:.1rem .3rem}
.toast.fail .x:hover{border-color:var(--ground)}
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
  var el, msg, code, dismiss;
  // Built once, from NODES rather than from markup: every string that lands in here is
  // written with textContent, so nothing a copy button carries can become an element.
  function build(){
    if(el) return;
    el=document.createElement('div'); el.className='toast'; el.setAttribute('role','status');
    var wrap=document.createElement('div');
    msg=document.createElement('span'); code=document.createElement('code');
    wrap.appendChild(msg); wrap.appendChild(code);
    dismiss=document.createElement('button');
    dismiss.type='button'; dismiss.className='x'; dismiss.textContent='×';
    dismiss.setAttribute('aria-label','Dismiss');
    dismiss.addEventListener('click', function(){ el.classList.remove('on','fail'); });
    el.appendChild(wrap); el.appendChild(dismiss);
    document.body.appendChild(el);
  }
  function toast(m){
    build(); clearTimeout(toast.t);
    msg.textContent=m; code.textContent=''; el.classList.remove('fail');
    el.classList.add('on');
    toast.t=setTimeout(function(){ el.classList.remove('on'); },3000);
  }
  // A FAILED COPY DOES NOT FADE. It stays up, it is selectable, and it shows the exact
  // text — see "A FAILED COPY IS A STICKY, SELECTABLE FAILURE" in this file's header.
  // The board is opened over file://, where a clipboard write can be refused outright,
  // and a three-second unselectable "copy failed" is barely better than the silent
  // failure it reports.
  function fail(text){
    build(); clearTimeout(toast.t);
    msg.textContent='Copy failed — this page cannot reach the clipboard. Select and copy this yourself:';
    code.textContent=text;
    el.classList.add('on','fail');
  }
  document.addEventListener('click', function(e){
    var b = e.target.closest ? e.target.closest('[data-copy]') : null;
    if(!b) return;
    // This is also what stops a copy button inside a <summary> from toggling the
    // <details> around it: the toggle is that click's DEFAULT ACTION, and cancelling
    // it here cancels that too. The ✕ on a project line copies without opening,
    // closing or navigating anything.
    e.preventDefault();
    var text = b.getAttribute('data-copy'), what = b.getAttribute('data-what') || 'Text';
    var ok = function(){ toast(what + ' copied — paste it to Claude'); };
    var bad = function(){ fail(text); };
    // BOTH paths are live on file://, and which one runs there was measured rather
    // than guessed — see the header. Chromium treats `file:` as trustworthy, so this
    // branch is taken and succeeds; legacy() covers the refusal, which is the case
    // that actually varies by browser and by focus.
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


# The shape a deliverable path may have, spelled ONCE and in the positive. Read this
# before adding another `if <something bad> in p: return None` below.
#
# FOUR ROUNDS OF REVIEW DEFEATED THE OTHER DESIGN, which anchored the PREFIX and then
# listed the characters it knew were bad. That asks "does this START right, and does it
# lack the one byte I thought of?" — so every round closed the reported vector and left
# the next one, and the simplest of them needed no exotic input at all:
#
#     /projects/p/deliverables/report.md /Users/somebody/Desktop/report.md
#
# Correct prefix, no `..`, no `#`, TWO paths in one value — rendered whole into a
# `data-copy` and labelled `report.md`, so nothing looked wrong. The value was never
# required to be a single, whole, well-formed path. Now it is:
#
#   segment  what a FILENAME may be made of, stated as a set rather than as the set's
#            complement: a word character (`\w` — Unicode-aware on a `str`, so a letter
#            in any script, a digit, `_`), then any run of word characters, `.`, `-`
#            and `+`.
#   marks    `\w` does NOT include a COMBINING MARK (Unicode category M), and a comment
#            here once claimed it did. macOS hands back decomposed filenames, so a
#            stamped `Übersicht.md` can arrive as `U` + U+0308 + `bersicht.md` and was
#            silently dropped — the "loses a real entry" class three rounds went to
#            eliminate. Marks are therefore removed from the string the shape is TESTED
#            on and kept in the string that is RETURNED. Stripping is safe because a
#            mark is decoration on the preceding base character: category M contains no
#            separator, no whitespace, no `#`, `:` or `/`, so removing them can only
#            turn a value the shape would have rejected into one it accepts, never
#            change what the accepted value points AT. It is also complete where
#            NFC-normalising is not — Devanagari matras, Thai vowel signs and Hebrew
#            points have no precomposed form and would still have been dropped.
#   whole    `/projects/<slug>/deliverables/` then one or more segments — and
#            fullmatch(), which is what makes "no trailing remainder" part of the shape
#            instead of one more separate check.
#
# WHY POSITIVE AND NOT ONE MORE EXCLUSION. The class here used to be `[^/\s#]+`, which is
# a denylist wearing a whitelist's clothes: it still had to have thought of every
# dangerous byte, and it had not thought of `:` —
#
#     /projects/p/deliverables/deck.md:/Users/victim/.ssh/id_rsa
#
# renders whole into a `data-copy`, labelled `id_rsa`. Appending `:` to the exclusions
# would be one more round of the same move. Stated positively there is nothing to
# enumerate: `/`, every kind of whitespace, `#`, `:`, `@`, `\`, ZWSP, BOM, U+2028 and the
# bidi overrides are all simply not in the set, and the next separator nobody has thought
# of is not in it either.
#
# TWO PERMISSIONS THAT CARRY RISK, NAMED RATHER THAN LEFT IMPLICIT:
#   · `.` — required (every extension has one). `.` and `..` as WHOLE segments are
#     impossible by construction, because a segment must begin with a word character,
#     so traversal needs no rule of its own.
#   · a word character in any script, plus any combining mark — so two filenames can be
#     homoglyphs (Cyrillic `а` vs Latin `a`), or differ only by an invisible mark, and
#     look alike on the page. Containment is unaffected: the value still resolves inside
#     this project's own `deliverables/`, which is the guarantee this guard makes.
#     Excluding non-ASCII instead would silently drop a legitimately stamped
#     `Übersicht.md`, which is the more likely event by far.
#
# WHAT IT COSTS, said plainly: a deliverable whose filename contains a space, `&`, `'`,
# `(`, `%` or `,` is dropped from the panel — visibly, because the count is computed from
# the same filtered list. Closeout resolves these names from `artifacts:` and a file can
# be renamed; an absolute path rendered onto a published page cannot be recalled.
#
# THE SLUG IS A SEGMENT LIKE ANY OTHER, which is the point: it is checked by the same
# rule rather than interpolated into a prefix and trusted, so `/projects/../deliverables/x`
# no longer walks out of the bundle when a hand-written SNAPSHOT.json says its slug is `..`.
DELIV_SEG = r"\w[\w.+-]*"
DELIV_PATH = re.compile(
    r"/projects/(%s)/deliverables/%s(?:/%s)*" % (DELIV_SEG, DELIV_SEG, DELIV_SEG))
# The same segment shape, on its own, for the one place a slug is joined to a real
# filesystem path (project_created). Stated as a reuse rather than a second literal:
# two spellings of "what a slug may be" is two things to drift.
SLUG_SEG = re.compile(DELIV_SEG)
# A date, and only a date. `timestamp:` is an ISO 8601 stamp, and anything after the
# day — the time, a `Z`, a trailing YAML comment, a second value somebody hand-edited
# in — is not rendered and cannot be. See project_created().
ISO_DAY = re.compile(r"\d{4}-\d{2}-\d{2}")


def bundle_deliverable(path, slug):
    """The path itself when it is a whole, well-formed deliverable path belonging to
    THIS project — otherwise None, and the entry is dropped from the panel AND from the
    count with it, never dropped from one while the other still reports it.

    NESTED paths (a research project shipping an exported site, e.g.
    `deliverables/site/index.html`) are deliberately allowed: they are still inside this
    project's own deliverables directory, which is the guarantee this guard keeps.

    Why the renderer re-checks at all, when closeout verified each path on disk before
    stamping it (close-project-folder.sh): the same rule href() applies to a PR URL's
    scheme. A writer having restricted what it collects is never a reason for the reader
    to trust it — a human can hand-edit project.md, and SNAPSHOT.json is a file on disk
    this renderer reads back without knowing who wrote it.
    """
    value = str(path or "")
    probe = "".join(c for c in value if unicodedata.category(c)[0] != "M")
    # THE SHAPE IS TESTED ON `probe`, SO THE SLUG IS PINNED ON `value`. Stripping marks
    # from the whole string also strips them from the slug, and `m.group(1) == slug`
    # would then read `/projects/p̈/deliverables/x.md` as project `p`'s own deliverable —
    # a button pointing at a NEIGHBOURING project's directory. Comparing the original
    # prefix closes that, and the slug is still checked as one well-formed segment by
    # the fullmatch above (which is what rejects a `..` or a `a/b` slug), so this is an
    # identity check on top of the shape check, not a return to trusting a prefix.
    if not DELIV_PATH.fullmatch(probe):
        return None
    return value if value.startswith("/projects/%s/deliverables/" % slug) else None


def project_created(d, slug):
    """`YYYY-MM-DD` from `<instance>/projects/<slug>/project.md`'s `timestamp:`, or "".

    The ONE read this renderer makes off disk that is not a snapshot, and the header's
    "THE ONE THING IT READS OFF DISK" block is where the case for it lives. Three
    things keep it inside the published-page rules, and each is a separate failure it
    would otherwise have:

      · THE SLUG IS SHAPE-CHECKED BEFORE IT TOUCHES A PATH. `slug` comes from a
        SNAPSHOT.json this renderer reads back without knowing who wrote it, and
        `d / "projects" / ".." / "project.md"` is a read outside `projects/` — the same
        traversal bundle_deliverable() already refuses, by the same rule, so there is
        one definition of "a slug" here rather than two.
      · ONLY A DATE IS TAKEN FROM THE VALUE. frontmatter() strips a trailing `#`
        comment for three enum fields and deliberately not for the rest, so the raw
        value of `timestamp: 2026-08-29T18:13:34Z  # see /Users/somebody/notes` still
        carries that path. Matching a leading `YYYY-MM-DD` and rendering the MATCH —
        never the value — means no byte outside `[0-9-]` can reach the page from this
        file, whatever else is on the line.
      · EVERY ABSENCE IS A BLANK, NEVER AN ERROR. No projects/ directory (every
        hand-written fixture), no project.md, an unreadable one, one with no
        frontmatter, one with no `timestamp:` — each renders no date and nothing else
        changes. A board must not fail because a document it does not need is missing.
    """
    if not SLUG_SEG.fullmatch(str(slug or "")):
        return ""
    try:
        text = (d / "projects" / str(slug) / "project.md").read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError, ValueError):
        return ""
    m = ISO_DAY.match(str(frontmatter(text).get("timestamp") or ""))
    return m.group(0) if m else ""


def task_core(p, tid):
    """`task-044` — the part of a handle that names the DOCUMENT.

    THE WHOLE PAGE HAS ONE NOTATION FOR A TASK, and this is it. It used to be
    `<slug>/tasks/task-044-the-dwd-calendar-grant-lives-in-…`: the filename, minus
    `projects/` and `.md`. That names a document and reads as a path, and the five
    controls in a waiting row each wrapped it in a different sentence, so an agent
    receiving one had to parse prose to find out which document was meant.

    SHORT ONLY WHILE SHORT RESOLVES. `task-044` is resolvable by exactly one glob —
    `projects/<slug>/tasks/task-044*.md` — which is deterministic while no two tasks in
    the project share the number. Nothing enforces that (validate-bundle.sh checks that
    references RESOLVE, not that ids are distinct), so this checks it here, per project,
    against the snapshot's own task list: where two ids do collide, BOTH fall back to
    the full id, which is unique because it is the filename. A handle that cannot be
    resolved is worse than a long one that can, and this way there is never one.
    """
    tid = str(tid or "")
    if not tid.startswith("task-"):
        return tid                      # not the convention: the id IS the handle
    n = task_number(tid)
    ids = [str(todict(x).get("id") or "") for x in tolist(p.get("tasks"))]
    same = [i for i in ids if i.startswith("task-") and task_number(i) == n]
    return "task-" + n if len(same) <= 1 else tid


def task_handle(p, tid, qn=None):
    """`<slug>/task-044`, or `<slug>/task-044/q1` for a question — the ONE handle shape.

    `q<n>` IS APPENDED ONLY FOR SOMETHING THAT IS A QUESTION. A verdict on a merge or
    on a promotion is not question-scoped, and inventing a `q1` for it would be the
    same fabrication q_split() exists to prevent, one level up: a reader would go
    looking for a question the item never had.

    THE SLUG IS SHAPE-CHECKED BEFORE IT IS COPIED, by the same rule the ✕ applies to it
    (SLUG_SEG) and for the same reason: this string comes from a SNAPSHOT.json read back
    without knowing who wrote it, and `"slug": "/Users/me/secret"` would otherwise put an
    absolute path inside a data-copy value — the one thing the no-filesystem-paths rule
    exists to prevent. It matters more than it used to: the handle now travels on the
    VERDICT buttons and on a project-level close item, and neither carried a slug before.
    A slug that is not one well-formed segment names no project a session could resolve
    either, so the handle drops it and names the task alone rather than copying a path —
    the control still identifies a document, and no path reaches the page.
    """
    core = task_core(p, tid)
    slug = str(p.get("slug") or "")
    if not SLUG_SEG.fullmatch(slug):
        slug = ""
    base = "/".join(x for x in (slug, core) if x)
    return "%s/q%d" % (base, qn) if (qn and base) else base


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


Q_BUTTON_CAP = 24


# A QUESTION IS NAMED BY THE `Q<n>` IT CARRIES, NEVER BY WHERE IT SITS IN A LIST.
#
# THE BUG THESE TWO PATTERNS EXIST TO KILL, because it is the kind that looks right on
# every board you have ever seen and is wrong on the one that matters: the labels used
# to be `range(1, open_questions + 1)` — a POSITION. A task whose Q1 had been answered
# and whose Q2 was still open rendered a button reading `answer Q1`. A human clicks it,
# opens the document, finds Q1 answered, and either answers the wrong question or stops
# believing the board. Positional numbering is not a fallback here and must never be
# reintroduced as one: it is the defect. `q_split()` below returns None rather than a
# guess, and every caller renders an honest unnumbered control for None.
#
# THE SHAPE A REAL ENTRY HAS, from the live documents this renders (SCHEMA.md, and
# `write-snapshot.sh`'s `yaml_list_entries`), is a stamped one:
#     "2026-08-30T16:01:52Z · Q2: should an instance that is behind the template …"
# so the token is NOT at the start of the string, and an escalated one carries a leading
# `advisor:` marker as well. Q_LEAD skips exactly that much and no more — at most one
# `·`-delimited segment of at most 40 characters (an ISO stamp plus its space is 21),
# with the marker allowed on either side of it. Bounded on purpose: an unbounded skip
# would hunt for a `Q7` mentioned in the middle of a question's PROSE and name the
# question after something it merely talks about.
# SPELLED WITHOUT `\s` AND `\b`, AND NOT BECAUSE PYTHON MINDS. It does not — these are
# Python `re` patterns and both escapes are portable there. The rule they obey is the
# repo's, and it is a STATIC one: this file is symlinked into instances on machines this
# repo never sees, where a GNU-only escape in a `grep`/`sed` is a silent wrong ANSWER
# rather than an error, so `tests/snapshot.test.sh` refuses either escape ANYWHERE in the
# shipped script. A file-wide ban is the only version of that check that can be trusted —
# one that tried to tell a Python region from a shell one would be a place for a real
# offender to hide. `[ \t\r\n]` is the same class here, and `(?![0-9A-Za-z_])` is exactly
# what the `\b` after a digit run meant: the number must END where it is read.
Q_LEAD = re.compile(
    r"^[ \t\r\n]*(?:advisor[ \t\r\n]*:[ \t\r\n]*)?"
    r"(?:[^·]{0,40}·[ \t\r\n]*)?(?:advisor[ \t\r\n]*:[ \t\r\n]*)?", re.I)
Q_NUM = re.compile(r"Q(\d{1,3})(?![0-9A-Za-z_])[:.)\]]?[ \t\r\n]*", re.I)

Q_BUTTON_CAP = 24


def q_split(q):
    """`(number, body)` for one open question — number is None when it names none.

    The number is read out of the question's own text and nowhere else. `Q01` and `Q1`
    are the same question, so the value is normalised through int(); three digits is the
    ceiling, which is far past any real document and keeps a drifted entry from
    producing an absurd label.
    """
    s = str(q)
    lead = Q_LEAD.match(s)
    if lead:
        s = s[lead.end():]
    m = Q_NUM.match(s)
    if m:
        return int(m.group(1)), s[m.end():].strip()
    return None, s.strip()


Q_LABEL = re.compile(r"Q0*(\d{1,3})", re.I)


def q_label_num(v):
    """The number in an `open_question_ids` entry — None for anything else.

    A LABEL IS PARSED, NEVER TRUSTED. write-snapshot.sh can emit only `Q` + digits or
    an empty string, but this reads a SNAPSHOT.json back without knowing who wrote it —
    the same rule href() applies to a PR URL's scheme. `""` (an honest "this question
    names no number") and `"nonsense"` (a hand-edited file) both come out as None, and
    None renders the unnumbered control rather than a fabricated number.
    """
    m = Q_LABEL.fullmatch(str(v or "").strip())
    return int(m.group(1)) if m else None


def q_handles(t):
    """One entry per open question — its number, or None when the board cannot know.

    THREE SOURCES, IN THIS ORDER, AND THE FIRST IS WHY THIS FIX EXISTS.
      · `open_question_ids` — one `Q<n>` label per question, carried by every snapshot
        written since 2026-08-31. This is the ONLY source present by default, and its
        absence was the whole defect: the two paths below are the pre-2026-08-31 pair,
        and on a default instance neither could ever produce a numbered handle, because
        the opt-in one was off and the other is a total. Measured on a real 8-project
        board before the field existed: `answer Q<n>` × 0, `answer question` × 18.
      · `open_question_text` — opt-in (SNAPSHOT_QUESTION_TEXT=1, off by default) and
        read here only for a snapshot too old to carry labels. Numbers come from
        q_split(), which reads the same rule the writer's question_labels() does.
      · `open_questions`, a plain COUNT → ONE unnumbered handle for the whole task, not
        N of them. N identical `?` buttons all copying the same string say nothing, and
        each one implies a question it cannot name. This is the honest floor, and it
        stays: a count is all an older or foreign snapshot has.
    The cap applies to the two per-question paths, where a drifted list of a thousand
    entries would otherwise render a page nobody can open; the count path emits one
    control regardless of how absurd the count is, so it needs no cap at all.
    """
    ids = tolist(t.get("open_question_ids"))
    if ids:
        return [q_label_num(x) for x in ids[:Q_BUTTON_CAP]]
    qs = [str(q) for q in tolist(t.get("open_question_text"))][:Q_BUTTON_CAP]
    if qs:
        return [q_split(q)[0] for q in qs]
    return [None] if toint(t.get("open_questions")) > 0 else []


# What an unnumbered handle says instead of a number. Two strings, because the two ways
# a number can be missing are not the same fact and a reader acts on them differently.
Q_NO_TEXT = ("The board carries a COUNT of open questions, not their numbers — this "
             "instance does not publish question text. Open %s and use the Qn written "
             "there; the board will not invent one.")
Q_NO_NUM = ("This question's text carries no Qn prefix, so the board cannot name it. "
            "Open %s and use the number written there; the board will not invent one.")


def q_title(t, ref):
    """The tooltip for an unnumbered handle — which of the two absences this is.

    `open_question_ids` counts as the question's own text having been read: the writer
    read it, found no `Qn`, and said so with an empty label. That is Q_NO_NUM, not
    Q_NO_TEXT — the board knows this question names no number, rather than not knowing
    whether it does.
    """
    read_it = tolist(t.get("open_question_ids")) or tolist(t.get("open_question_text"))
    return (Q_NO_NUM if read_it else Q_NO_TEXT) % ref


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
            # once, in prose, where it came from — then drop the marker, so the
            # question does not read "Q2: advisor: …". q_split() removes it along with
            # the entry's stamp, and returns the number THE QUESTION NAMES.
            escalated = any(q.lower().lstrip().startswith("advisor:") for q in qs)
            lead = ("The advisor raised this and the project-manager could not settle it from "
                    "the documents, so it came to you. ") if escalated else ""
            # A question with no number of its own is rendered as its text alone. It was
            # numbered by POSITION here too — so a stamped entry reading `… · Q2: …`
            # came out as "Q1: 2026-08-30T16:01:52Z · Q2: …", naming it twice and
            # getting it wrong the first time. Never label a question by its index.
            def one(q):
                n, body = q_split(q)
                return ("Q%d: %s" % (n, body)) if n else body
            body = "  ".join(one(q) for q in qs)
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

    rows, asks, others = [], [], []
    n_tasks = n_done = 0
    for s, d in zip(instances, inst_dirs):
        g = s.get("group", "?")
        me, default_owner = who_and_default(d)
        others += others_for(d, me, default_owner)
        for p in tolist(s.get("projects")):
            p = todict(p)
            # Somebody else's project renders ONCE, below, from HEAD. Skipping it here is
            # what stops the two sections from showing the same work twice — the failure
            # a naive "append a second section" produces, and one that looks fine.
            #
            # The one thing this drops: a project owned by somebody else that exists in
            # YOUR working tree and is not committed yet. It is skipped here and HEAD has
            # never heard of it, so it appears nowhere. That is the honest answer rather
            # than a gap — an uncommitted document is not something the other clone can
            # see either, and committing it is what publishes it to both boards.
            if not is_mine(owner_of(p, default_owner), me):
                continue
            ts = [todict(t) for t in tolist(p.get("tasks"))]
            # "Done" is all-tasks-terminal, or the project saying so. A project with no
            # tasks yet is NOT done — it has not started.
            done_proj = bool(p.get("status") == "done" or (
                ts and all(t.get("status") in TERMINAL for t in ts)))
            # THIS project's rail items, collected into their own list rather than only
            # into the pooled one. `asks` still exists and is still the page-wide count
            # in the masthead tally; what changed is that the list is also carried on
            # the row, so the block renders INSIDE the project it belongs to and the
            # summary line can weigh it. Same items, same order, same derivation.
            mine = []
            for t in ts:
                n_tasks += 1
                if t.get("status") == "done":
                    n_done += 1
                # A TERMINAL TASK IS NOT WAITING ON YOU, and this is a DIFFERENT defect
                # from the Q-number one above — decided on its own, not absorbed by it.
                #
                # `done`/`cancelled` reached this list through the presentation-layer
                # branch below, so a finished task with a stale unanswered question sat
                # under "Waiting for you" for good. The other reading — that it is a real
                # loose end — loses on two counts. It is not TRUE: the paragraph the rail
                # writes for it says "an unanswered question blocks promotion, so the loop
                # will not dispatch this task", and nothing about that is so for a task
                # that already shipped; the loop will not dispatch it whatever you answer.
                # And it is not ACTIONABLE: answering changes no state any tick reads, so
                # the item can never be cleared from this page by doing what the page asks
                # — only by editing the document. A queue that cannot be emptied by acting
                # on it is the thing that teaches a human to stop reading the queue.
                # The loose end is real; the place to raise it is the document, not the
                # list of things blocking you today.
                #
                # The guard is on the WHOLE task contribution, not just the branch below,
                # so a hand-edited snapshot carrying `"status":"done","awaiting":"merge"`
                # is caught too. write-snapshot.sh emits an awaiting verb only for draft /
                # in-review / blocked, so this costs nothing on a snapshot it wrote.
                # A project's own `awaiting_close` is untouched: it is project-level, it
                # is exactly what a finished project SHOULD ask for, and `.proj.fin.wants`
                # exists to render it.
                if t.get("status") in TERMINAL:
                    continue
                if t.get("awaiting"):
                    mine.append((g, p, t, None))
                elif t.get("open_questions"):
                    # A question only produces an `awaiting` verb while the task is a
                    # DRAFT (write-snapshot.sh, `case draft)`), so a question on a
                    # ready or in-progress task is invisible in the queue. Surfacing
                    # it here fixes that at the presentation layer, without touching
                    # the AWAITING.md contract that awaiting-queue.test.sh pins.
                    mine.append((g, p, dict(t, awaiting="question"), None))
            if p.get("awaiting_close"):
                mine.append((g, p, {"awaiting": "close", "title": "all tasks terminal",
                                    "id": ""}, "/close-project " + str(p.get("slug") or "")))
            asks += mine
            rows.append((g, p, done_proj, project_created(d, p.get("slug")), mine))

    # Finished projects sink to the bottom, and WITHIN each half a project that wants
    # you rises above one that does not — the third channel of the awaiting weighting
    # (see the header), and the one that survives a reader who cannot see colour or a
    # phone that shows four rows at a time. Everything else keeps the snapshot's order,
    # so the list does not reshuffle between renders. `sort` is stable, which is what
    # makes "within each half" true rather than approximately true.
    rows.sort(key=lambda r: (r[2], not r[4]))

    head = [TABLE_HEAD.replace("__TITLE__", e(title))]
    o = ['<div class="board">']

    o.append('<header class="mast"><div><h1>%s</h1>' % e(title))
    stamps = sorted(str(s.get("generated_at") or "") for s in instances if s.get("generated_at"))
    if stamps:
        o.append('<p class="sub">Snapshot %s UTC</p>'
                 % e(stamps[-1].replace("T", " ").replace("Z", "")))
    # WHAT IS LEFT OF THE POOLED QUEUE, and all that is left of it: one line saying how
    # many projects to look for. The list itself is inside those projects now (see the
    # header), so this says where to look rather than repeating what is there — a
    # second copy of sixteen items is the thing being deleted, not something to shrink.
    n_wanting = sum(1 for r in rows if r[4])
    if asks:
        o.append('<p class="sub">%d waiting on you, in %d project%s — marked and sorted '
                 "to the top below.</p>"
                 % (len(asks), n_wanting, "" if n_wanting == 1 else "s"))
    o.append("</div><dl class=\"tally\">")
    o.append('<div><dt>Projects</dt><dd>%d</dd></div>' % len(rows))
    o.append('<div><dt>Done</dt><dd>%d/%d</dd></div>' % (n_done, n_tasks))
    o.append('<div class="%s"><dt>Awaiting you</dt><dd>%d</dd></div>'
             % ("live" if asks else "", len(asks)))
    o.append("</dl></header>")

    for d, msg in broken:
        o.append('<div class="snapnote"><strong>Unreadable snapshot.</strong> '
                 '<code>%s/SNAPSHOT.json</code> could not be parsed, so that instance is '
                 'not on the board. Re-run <code>write-snapshot.sh</code> there. '
                 '<br>%s</div>' % (e(d), e(msg)))

    # ---- one project's decision rail: one click copies a complete prompt ----
    #
    # This was a single pooled `<section class="rail">` above every project until
    # 2026-08-30. It is now called once per project, from inside that project's own
    # <details>, with only that project's items — the markup of an item is UNCHANGED,
    # which is deliberate: the move is where the list is rendered, not what an item
    # says, and `.where` still carries `<group> › <project>` because a board can show
    # more than one instance and the close hint rides in that same span.
    def rail(items):
        if not items:
            return
        o.append('<section class="rail"><h2>Waiting for you · %d</h2><ul>' % len(items))
        for g, p, t, hint in items:
            # str() on the id, not just on the title: a snapshot carrying `"id": 5`
            # parses, so the malformed-snapshot path never sees it, and `5 + " ("` then
            # raised TypeError — which meant NO FILE WAS WRITTEN AT ALL, one drifted
            # instance blanking the published board for every healthy one. Same class as
            # toint() above, and the reason nothing here concatenates snapshot data raw.
            tid_txt = str(t.get("id") or "")
            where = g + " › " + str(p.get("title") or "")
            o.append('<li class="ask"><details class="why"><summary class="line">'
                     '<span class="verb">%s</span>' % e(t.get("awaiting")))
            # THE FILENAME, BEFORE THE TITLE. A title is not a filename, and the reader
            # of this row is trying to open the document — `012-claim-identity` is what
            # they type into a file tree. Same form the task table's first column shows
            # (`task-` and `.md` both dropped: constant, so neither carries information),
            # and the close item has no task id at all, so it gets none.
            if tid_txt:
                o.append('<span class="tid">%s</span>'
                         % e(tid_txt[5:] if tid_txt.startswith("task-") else tid_txt))
            o.append('<span class="what">%s</span>' % e(t.get("title")))
            o.append('<span class="where">%s%s</span></summary>'
                     % (e(where), " · <code>%s</code>" % e(hint) if hint else ""))
            o.append('<p>%s</p></details>' % e(explain(t.get("awaiting"), p, t, hint)))
            # ONE HANDLE, AND EVERY BUTTON IN THIS ROW OPENS WITH IT. `<handle>: ` is
            # the whole notation — the task's own for anything task-scoped, this
            # question's for a question, and the project's alone for a close proposal,
            # which names no task. What follows the colon is what the button MEANS;
            # nothing after it has to be parsed to find out what it is about.
            ref = task_handle(p, tid_txt)
            o.append('<div class="acts">')
            if tid_txt:
                o.append('<button class="ghost" data-copy="%s" data-what="Task handle">'
                         "copy task ref</button>" % e(ref + ": "))
                for qn in q_handles(t):
                    # The number comes from the question itself (its `Q<n>` label, or
                    # its text on an older snapshot), never from this loop's position.
                    # No number ⇒ no number is shown, and no `/q<n>` segment is added:
                    # a handle that named `q1` here would send a reader to a question
                    # the board just admitted it cannot name.
                    if qn is None:
                        o.append('<button class="qbtn nonum" data-copy="%s" '
                                 'data-what="Task handle" title="%s">'
                                 "answer question</button>"
                                 % (e(ref + ": "), e(q_title(t, ref))))
                    else:
                        qref = task_handle(p, tid_txt, qn)
                        o.append('<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                                 'title="Copy &quot;%s: &quot; ready to type your answer after">'
                                 "answer Q%d</button>"
                                 % (e(qref + ": "), qn, e(qref), qn))
            for verdict, (label, cls, lead) in ([] if t.get("awaiting") == "question"
                                                else WORDING.items()):
                # THE HANDLE, THEN THE VERDICT — not a sentence describing which item
                # this was. It used to read `APPROVED — go ahead. Re the "merge" item
                # on <task title> in <project title>.`, so the agent receiving it had
                # to parse prose to work out which document was meant, which is the
                # failure class this page exists to delete. The wording after the colon
                # is unchanged: a human pastes it verbatim and it is unambiguous.
                #
                # NO `/q<n>` HERE, EVER. A verdict is given on the ITEM — a merge, a
                # promotion, a close, or a task's questions as a whole — and no control
                # on this page binds one to a single question. `<handle>/q1: REJECTED`
                # would name a question nobody rejected.
                # APPROVE IS GENERIC OVER THE AWAITING KINDS, so its payload is not.
                # One button serves a promotion, a merge, a project close and a
                # deliverable, and only the FIRST of those is the same decision as the
                # task table's `promote → ready`. So a promotion item copies PROMOTE —
                # the same bytes that button copies — and every other kind keeps the
                # verdict sentence, because `promote to ready` on a merge or a close
                # names an act nobody asked for. Driven off the item's own awaiting
                # verb, never off WORDING: editing the entry would have changed all
                # four.
                if verdict == "approve" and t.get("awaiting") == "approve":
                    msg = "%s: %s" % (ref, PROMOTE)
                else:
                    msg = "%s: %s" % (ref, lead)
                    if verdict == "approve" and hint:
                        msg += " Run %s." % hint
                    elif verdict == "discuss":
                        msg += " Tell me the trade-off you see and what you recommend."
                    elif verdict == "reject":
                        msg += " Record why on the task; leave its status as it is."
                o.append('<button class="%s" data-copy="%s" data-what="%s">%s</button>'
                         % (cls, e(msg), e(label + " prompt"), e(label)))
            o.append("</div></li>")
        o.append("</ul></section>")

    # ---- one <details> per project, collapsed by default -------------------
    n_fin = sum(1 for r in rows if r[2])
    for idx, (g, p, fin, created, mine) in enumerate(rows):
        if fin and (idx == 0 or not rows[idx - 1][2]):
            o.append('<h2 class="sep">Finished · %d</h2>' % n_fin)
        tasks = [todict(t) for t in tolist(p.get("tasks"))]
        nd = sum(1 for t in tasks if t.get("status") == "done")
        nr = sum(1 for t in tasks if t.get("status") in RUNNING)
        nw = sum(1 for t in tasks if t.get("status") in PENDING)
        ph = todict(p.get("phase_progress"))
        # From project.md's `deliverable_paths:` ONLY — never `tasks/`, never a
        # filesystem listing of `deliverables/`. That is what keeps this panel
        # compatible with the done-project skip (write-snapshot.sh): a retained
        # project's `tasks` list above is already empty, and this does not change
        # that. Reject anything that is not this project's own bundle-relative
        # shape before it ever reaches a button.
        dps = [d for d in (bundle_deliverable(x, str(p.get("slug") or ""))
                           for x in tolist(p.get("deliverable_paths"))) if d]
        slug = str(p.get("slug") or "")
        o.append('<details class="proj%s%s"><summary class="phead">'
                 % (" fin" if fin else "", " wants" if mine else ""))
        o.append('<span class="ptitle">%s</span>' % e(p.get("title")))
        # THE DATE SITS WITH THE TITLE, not at the far end of the line. It qualifies the
        # title — "this project, started then" — and reading it meant crossing six count
        # chips to get to it. Same span, same class, same treatment; only the position
        # moved, and `.counts` keeps its own place by taking the free space instead of
        # being pushed there by `.ptitle`.
        if created:
            o.append('<span class="pdate" title="Project created %s">%s</span>'
                     % (e(created), e(created)))
        o.append('<span class="counts">')
        if fin:
            o.append('<span class="c done-tag">✓ done</span>')
        o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
        if not fin:
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
        if mine:
            # THE SIGNAL, and the reason collapsing sixteen projects is not a
            # regression — see the header's WEIGHTING block for the other two channels
            # (the card's own marking, and the sort). It is a count of this project's
            # rail items, which is exactly what the pooled list above used to
            # contribute for it.
            #
            # ONE PILL, WHERE THERE WERE TWO. A project header used to carry BOTH a
            # filled `N awaiting you` at the front of the row and an outlined
            # `N questions` at the end of it. They measure overlapping things — every
            # open question on a draft is also an awaiting item — and the narrower one
            # was last, so a reader had to work out which to trust. The questions
            # counter is gone and this pill took its slot and its treatment: same
            # place, same outlined signal styling, the AWAITING count.
            # WHAT THAT COSTS AND WHY IT IS AFFORDABLE: the filled treatment was one of
            # the three channels, and it is the one that went. The other two are
            # untouched and are the ones that do not depend on noticing a chip — the
            # whole card is bordered and inset-barred (`.proj.wants`), and a project
            # that wants you sorts above one that does not. The pill is still the only
            # one on the line in the signal colour.
            o.append('<span class="c you"><b>%d</b> awaiting you</span>' % len(mine))
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
        if dps:
            o.append('<span class="tag">%d deliverable%s</span>'
                     % (len(dps), "" if len(dps) == 1 else "s"))
        o.append("</span>")
        if SLUG_SEG.fullmatch(slug):
            # THE ✕ COPIES A COMMAND. It does not close, mutate or navigate anything —
            # see the header, and do not reword this tooltip into "close this project".
            # It is a plain [data-copy] button on the ONE clipboard helper this page
            # already ships, so it adds no script, no link and no second implementation;
            # the helper's preventDefault is what keeps a click inside this <summary>
            # from toggling the card open.
            #
            # THE SHAPE CHECK, not a truthiness test, and for the reason every other
            # value on this page is shape-checked: a slug comes from a SNAPSHOT.json
            # read back without knowing who wrote it, and `"slug": "/Users/me/secret"`
            # would otherwise put an absolute path inside a data-copy value — the one
            # thing the whole no-filesystem-paths rule exists to prevent. A slug that
            # is not one well-formed segment names nothing `/close-project` could act
            # on either, so dropping the control loses nothing real.
            o.append('<button class="pclose" data-copy="/close-project %s" '
                     'data-what="Close command" title="Copy the command to close this '
                     'project (%s) — this button only copies; closing is something you '
                     'run yourself">✕</button>'
                     % (e(slug), e("/close-project " + slug)))
        o.append("</summary>")

        o.append('<div class="body">')
        # THIS project's queue, above its task table and holding only its own items.
        rail(mine)
        # THERE IS NO ROLE COLUMN, AND IT IS NOT CONDITIONAL — IT IS GONE.
        #
        # It went through both weaker forms first, and both are recorded because both look
        # reasonable enough to be proposed again. It was unconditional; then conditional on
        # `len(roles) > 1`, on the reasoning that a column with one value is not a column
        # but a rare `devops-engineer` row is real information; then, briefly, that AND not
        # phased. Every version kept the same defect: on the boards this was measured
        # against, the column either said nothing on every row or said something on one
        # project out of twelve, and it cost the task name width on all of them. A reader
        # who wants to know who is on a task opens the task — `assignee:` is in the
        # document and in AWAITING.md, neither of which this deletion touches.
        #
        # WHAT THE CONDITION COST, since that is the part worth not repeating: a column
        # present on one card and absent on the next is self-describing but not scannable,
        # and the predicate had to be kept in step across a <thead> and a per-row <td> —
        # two places, where a mismatch shifts every value one column left and renders a
        # table nobody can read. Deleting the column deletes the predicate, so there is no
        # longer anything for the header and the body to disagree about.
        # Owner ruling, 2026-08-31. Do not reintroduce it, conditionally or otherwise,
        # without deleting this paragraph.
        o.append('<div class="scroll"><table><thead><tr>'
                 "<th>Task</th><th>State</th><th>Depends on</th>"
                 "<th class=\"r\">Q</th><th>PR</th>"
                 "</tr></thead><tbody>")
        for t in tasks:
            tid = str(t.get("id") or "")
            short = tid[5:] if tid.startswith("task-") else tid
            st = str(t.get("status") or "")
            o.append('<tr%s>' % (' class="flight"' if t.get("in_flight") else ""))
            # TWO COLUMNS INSIDE ONE CELL, and the wrapper is what makes them possible:
            # `display:flex` ON a <td> takes it out of the table's own column sizing, so
            # the filename column lives in a <div> the cell contains. `.trow` is a flex
            # COLUMN at every width — filename line 1, title line 2, EVERY row the same.
            # It used to become a row above 1200px, with the filename in a fixed column;
            # see the `.trow` rules for why that second layout is gone rather than tuned.
            o.append('<td><div class="trow"><span class="tfile"><span class="tid">%s</span>'
                     % e(short))
            if st == "draft":
                # THE PROMOTE CONTROL SITS ON THE FILENAME'S OWN LINE, immediately after
                # it — inside `.tfile`, which is the filename line. It was a sibling of
                # the title, i.e. a THIRD line (filename, then the control, then the
                # title), so the one row on the board asking for an action was also the
                # only row a third taller than its neighbours. Here it costs no line at
                # all: `.tfile` is one line either way, and `flex-wrap:wrap` is what
                # keeps that true when a filename leaves it no room.
                # It still only COPIES a prompt: promoting is `status: ready` in the
                # document, a human authority (SCHEMA.md), and nothing here does it.
                # THE HANDLE, THEN THE VERB — the notation every other control on this
                # page uses, and the same string the rail's Approve copies (PROMOTE).
                promo = "%s: %s" % (task_handle(p, tid), PROMOTE)
                o.append('<button class="promote" data-copy="%s" data-what="Promotion prompt">'
                         "promote → ready</button>" % e(promo))
            o.append('</span><div class="tmain">')
            o.append('<button class="tbtn" data-copy="%s" data-what="Task handle">%s</button>'
                     % (e(task_handle(p, tid)), e(t.get("title"))))
            o.append("</div></div></td>")
            o.append('<td><span class="state %s">%s</span></td>' % (TONE.get(st, ""), e(st)))
            deps = [str(d) for d in tolist(t.get("depends_on"))]
            if deps:
                # Show the short id, the same form the Task column shows, and copy the
                # same handle every other control on the page copies — a dependency is
                # most useful as a thing to go read, and it is read by the same means.
                # SPACE-SEPARATED, exactly as the PR cell joins its refs. A comma
                # between two pills is one more character and no more information.
                o.append('<td class="deps">%s</td>' % " ".join(
                    '<button class="dep" data-copy="%s" data-what="Task handle" title="%s">%s</button>'
                    % (e(task_handle(p, d)), e(d),
                       e(task_number(d))) for d in deps))
            else:
                o.append('<td class="dim">—</td>')
            handles = q_handles(t)
            if handles:
                # ONE HANDLE PER QUESTION, LABELLED BY THE NUMBER THE QUESTION CARRIES.
                # This used to derive the labels from the COUNT — `Q1 … QN` — on the
                # reasoning that SCHEMA.md asks every entry to be numbered contiguously
                # from Q1. It asks; it does not enforce, and answering Q1 leaves Q2 open
                # and the count at 1, so the assumption broke on the first real task it
                # met and put the wrong number on the button. A `?` that admits it does
                # not know is worth more than a number that is confidently wrong.
                ref = task_handle(p, tid)
                o.append('<td class="r"><span class="qs">%s</span></td>' % "".join(
                    ('<button class="qbtn nonum" data-copy="%s" data-what="Task handle" '
                     'title="%s">?</button>' % (e(ref + ": "), e(q_title(t, ref))))
                    if qn is None else
                    ('<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                     'title="Copy &quot;%s: &quot; ready to type your answer after">'
                     'Q%d</button>' % (e(task_handle(p, tid, qn) + ": "), qn,
                                       e(task_handle(p, tid, qn)), qn))
                    for qn in handles))
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
            o.append('<td class="prs">%s</td></tr>' % (" ".join(cells) if cells
                                                       else '<span class="dim">—</span>'))
        o.append("</tbody></table></div>")
        if dps:
            # Reuses the ONE clipboard helper the page already ships (TABLE_SCRIPT,
            # `[data-copy]`/`data-what`) — no second script, no new event handler.
            # The label shown is just the filename; the full bundle-relative path is
            # both the copied text and the hover title, so a reader can see what a
            # click will paste before clicking it.
            o.append('<div class="delivs"><h3>Deliverables · %d</h3><ul>' % len(dps))
            for dp in dps:
                fname = dp.rsplit("/", 1)[-1]
                o.append('<li><button class="dlv" data-copy="%s" data-what="Deliverable path" '
                         'title="%s">%s</button></li>' % (e(dp), e(dp), e(fname)))
            o.append("</ul></div>")
        o.append("</div></details>")

    # ---- the other owners, one collapsed block each, from git HEAD ----------
    # NAMED and COLLAPSED. No `open` attribute, and no script — the same <details> the
    # projects above use, for the same reasons. The collapse is ergonomics: this is
    # context, not your queue. It hides nothing, and the footer says so.
    by_owner = {}
    for x in others:
        x = todict(x)
        by_owner.setdefault(str(x.get("owner") or "?"), []).append(x)
    if by_owner:
        o.append('<h2 class="sep">Other owners · %d</h2>' % len(by_owner))
        for who in sorted(by_owner, key=lambda s: s.lower()):
            entries = by_owner[who]
            nd = sum(toint(x.get("done")) for x in entries)
            nr = sum(toint(x.get("running")) for x in entries)
            nw = sum(toint(x.get("pending")) for x in entries)
            o.append('<details class="proj other"><summary class="phead">')
            o.append('<span class="ptitle">%s</span><span class="counts">' % e(who))
            o.append('<span class="c"><b>%d</b> project%s</span>'
                     % (len(entries), "" if len(entries) == 1 else "s"))
            o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
            o.append("</span></summary>")
            o.append('<div class="body"><div class="scroll"><table><thead><tr>'
                     "<th>Project</th><th>Where</th><th>State</th>"
                     "<th class=\"r\">Done</th><th class=\"r\">Running</th>"
                     "<th class=\"r\">Pending</th></tr></thead><tbody>")
            for x in entries:
                st = str(x.get("status") or "")
                # BUNDLE-RELATIVE, always. `/projects/<slug>/` is the same form the copy
                # buttons above use and the only kind of path allowed to reach this page:
                # a published board must not carry anybody's home directory.
                o.append('<tr><td>%s</td><td class="dim"><code>/projects/%s/</code></td>'
                         '<td><span class="state %s">%s</span></td>'
                         '<td class="r">%d</td><td class="r">%d</td><td class="r">%d</td></tr>'
                         % (e(x.get("title")), e(x.get("slug")), TONE.get(st, ""), e(st),
                            toint(x.get("done")), toint(x.get("running")),
                            toint(x.get("pending"))))
            o.append("</tbody></table></div>"
                     "<p class=\"where\">Read from the tracked documents at this clone’s "
                     "current <code>HEAD</code> — never from another clone’s snapshot, "
                     "which is gitignored and never present here. It moves when you pull, "
                     "and it never shows uncommitted work.</p></div></details>")

    o.append('<footer><p>Derived from each instance’s <code>SNAPSHOT.json</code> and '
             "<strong>as sensitive as the task documents it comes from</strong>. Titles are "
             "human-written free text; no customer PII belongs in a task title, and so none "
             "belongs here. Task descriptions, document bodies, question and blocker text, "
             "author email addresses and out-of-bundle paths are never carried.</p>"
             "<p>Project owners are carried, on purpose, so this board can tell your work "
             "from theirs — so the <strong>names of other owners are on this page whether "
             "their section is open or shut</strong>. Collapsing it is for reading comfort, "
             "not privacy.</p>"
             "<p>A browser cannot open a local file, so every control here copies a "
             "<em>handle</em> instead: <code>&lt;project&gt;/task-&lt;n&gt;</code>, plus "
             "<code>/q&lt;n&gt;</code> when it names one question. Paste it into a session "
             "on your instance — the document is "
             "<code>projects/&lt;project&gt;/tasks/task-&lt;n&gt;*.md</code>. Decision "
             "buttons copy that same handle and then what the button means; the bundle, "
             "not this page, is where a decision is recorded.</p></footer></div>")
    o.append(TABLE_SCRIPT)
    return head, o, len(asks)


# ---------------------------------------------------------------- write it out
if not instances:
    # Publishing an empty page is not useful, so nothing is written at all. Exit 0
    # anyway: an instance off the board is a choice, not an error.
    print("build-board: no readable snapshot; nothing written.", file=sys.stderr)
    sys.exit(0)

head, parts, n_awaiting = render_table()

head_html = "\n".join(head)
body_html = "\n".join(parts)
if STANDALONE:
    doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
           + head_html + "\n</head>\n<body>\n" + body_html + "\n</body>\n</html>\n")
else:
    doc = head_html + "\n" + body_html + "\n"
# The output DIRECTORY is created, and only here — after the "nothing to write" exit
# above, so an instance that is off the board still leaves no trace. The /pm-loop tick
# renders to `.board-live/board.html`, which exists on a machine that has run
# watch-board.sh and on no other, and a renderer that fails with a FileNotFoundError the
# first time each tick calls it would be a board nobody ever sees.
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(doc, encoding="utf-8")
print(f"build-board: wrote {OUT} — {len(instances)} instance(s), "
      f"{n_awaiting} awaiting, {len(broken)} unreadable snapshot(s).")
PY
